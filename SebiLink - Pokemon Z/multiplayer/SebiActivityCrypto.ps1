param(
  [ValidateSet('Library','Setup','AdminSetup','Writer','View')][string]$Mode = 'Library',
  [string]$ConfigDir,
  [string]$PipeName,
  [int]$ParentId = 0,
  [string]$KeyFile,
  [string]$HistoryFile,
  [string]$PublicKeyFile,
  [switch]$UseConsole
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
if (!('SebiHistoryVault' -as [type])) {
Add-Type -ReferencedAssemblies System.Security,System.Core -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Diagnostics;
using System.Text.RegularExpressions;
using System.Threading;

public sealed class SebiHistoryVault : IDisposable {
  const int Iterations = 250000;
  static readonly byte[] Magic = Encoding.ASCII.GetBytes("SEBIENC1");
  static readonly byte[] PublicMagic = Encoding.ASCII.GetBytes("SEBIENC2");
  static readonly byte[] AdminMagic = Encoding.ASCII.GetBytes("SEBIKEY1");
  static readonly byte[] Entropy = Encoding.ASCII.GetBytes("SebiLink-PokemonZ-History-v1");
  static readonly UTF8Encoding Utf8 = new UTF8Encoding(false, true);
  string journal, statePath;
  byte[] header, keys, previous;
  long sequence;
  FileStream file;
  HashSet<string> nativeEvents = new HashSet<string>();
  // Only history-owned paths migrate; game preferences stay beside Historial.
  static bool HistoryFile(string name) {
    return name.StartsWith("historial.",StringComparison.OrdinalIgnoreCase) || name.StartsWith("historial-",StringComparison.OrdinalIgnoreCase) || name.Equals("Ver historial SebiLink.bat",StringComparison.OrdinalIgnoreCase);
  }
  static void RejectLink(string path) {
    if ((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0) throw new IOException("La carpeta del historial no admite enlaces de archivos.");
  }
  static void CollectHistory(string directory, List<string> files, List<string> folders) {
    RejectLink(directory); folders.Add(directory);
    foreach (string path in Directory.GetFiles(directory)) { RejectLink(path); files.Add(path); }
    foreach (string path in Directory.GetDirectories(directory)) CollectHistory(path,files,folders);
  }
  public static string PrepareDirectory(string directory) {
    string supplied=Path.GetFullPath(directory).TrimEnd(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar);
    string root=Path.GetFileName(supplied).Equals("Historial",StringComparison.OrdinalIgnoreCase) ? Path.GetDirectoryName(supplied) : supplied;
    string target=Path.Combine(root,"Historial"); Directory.CreateDirectory(root); RejectLink(root);
    string mutexName;
    using (SHA256 sha=SHA256.Create()) mutexName="Local\\SebiHistoryFolder-"+BitConverter.ToString(sha.ComputeHash(Utf8.GetBytes(root.ToUpperInvariant()))).Replace("-","");
    using (Mutex mutex=new Mutex(false,mutexName)) {
      bool held=false;
      try {
        try { held=mutex.WaitOne(10000); } catch (AbandonedMutexException) { held=true; }
        if (!held) throw new IOException("La carpeta del historial esta ocupada; vuelve a intentarlo.");
        if (Directory.Exists(target)) RejectLink(target);
        List<string> files=new List<string>(), folders=new List<string>();
        foreach (string path in Directory.GetFiles(root)) if (HistoryFile(Path.GetFileName(path))) { RejectLink(path); files.Add(path); }
        foreach (string path in Directory.GetDirectories(root)) {
          string name=Path.GetFileName(path);
          if (name.Equals("history-viewer",StringComparison.OrdinalIgnoreCase) || name.Equals("history-pending",StringComparison.OrdinalIgnoreCase) || name.StartsWith(".public-history-migration-",StringComparison.OrdinalIgnoreCase) || name.StartsWith(".upgrade-history-",StringComparison.OrdinalIgnoreCase) || name.StartsWith(".history-migration-",StringComparison.OrdinalIgnoreCase)) CollectHistory(path,files,folders);
        }
        List<FileStream> locks=new List<FileStream>();
        try {
          // Share Delete permits moving our open files but excludes an active writer.
          // Check every collision/lock before moving anything; retries resume safely.
          foreach (string path in files) {
            FileStream source=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Delete); locks.Add(source);
            string destination=Path.Combine(target,path.Substring(root.Length+1));
            if (Directory.Exists(destination)) throw new IOException("Conflicto al reunir el historial; se conservan los archivos.");
            string parent=Path.GetDirectoryName(destination);
            while (parent.Length>=target.Length) { if (File.Exists(parent)) throw new IOException("Conflicto de carpetas del historial."); if (Directory.Exists(parent)) RejectLink(parent); parent=Path.GetDirectoryName(parent); if (parent==null) break; }
            if (File.Exists(destination)) {
              RejectLink(destination);
              FileStream existing=new FileStream(destination,FileMode.Open,FileAccess.Read,FileShare.Delete); locks.Add(existing);
              using (SHA256 sha=SHA256.Create()) if (source.Length!=existing.Length || !Same(sha.ComputeHash(source),sha.ComputeHash(existing))) throw new IOException("Hay dos historiales distintos. No se reemplaza ninguno.");
            }
          }
          Directory.CreateDirectory(target);
          foreach (string path in folders) Directory.CreateDirectory(Path.Combine(target,path.Substring(root.Length+1)));
          foreach (string path in files) {
            string destination=Path.Combine(target,path.Substring(root.Length+1));
            if (File.Exists(destination)) File.Delete(path); else File.Move(path,destination);
          }
        } finally { foreach (FileStream stream in locks) stream.Dispose(); }
        for (int i=folders.Count-1;i>=0;i--) Directory.Delete(folders[i],false);
        return target;
      } finally { if (held) mutex.ReleaseMutex(); }
    }
  }
  static string NativeId(string json) {
    Match match = Regex.Match(json, "\"native_audit_id\"\\s*:\\s*\"([a-f0-9]{32})\"");
    return match.Success ? match.Groups[1].Value : null;
  }
  public static void QueueEvent(string directory, string json) {
    if (String.IsNullOrEmpty(json) || json.Length > 8000000 || NativeId(json)==null) throw new InvalidDataException("Registro nativo invalido.");
    string queue=Path.Combine(directory,"history-pending"); Directory.CreateDirectory(queue);
    byte[] plain=Utf8.GetBytes(json);
    try { Atomic(Path.Combine(queue,DateTime.UtcNow.Ticks.ToString("D19")+"-"+Guid.NewGuid().ToString("N")+".audit"),ProtectedData.Protect(plain,Entropy,DataProtectionScope.CurrentUser)); }
    finally { Array.Clear(plain,0,plain.Length); }
  }
  public void DrainPending(string directory, string observedContext) {
    string queue=Path.Combine(directory,"history-pending");
    if (!Directory.Exists(queue)) return;
    string[] paths=Directory.GetFiles(queue,"*.audit"); Array.Sort(paths,StringComparer.Ordinal);
    foreach (string path in paths) {
      byte[] plain=ProtectedData.Unprotect(File.ReadAllBytes(path),Entropy,DataProtectionScope.CurrentUser);
      try {
        string json=Utf8.GetString(plain), id=NativeId(json);
        if (id==null || !json.StartsWith("{")) throw new InvalidDataException("Registro nativo alterado.");
        if (!nativeEvents.Contains(id)) {
          if (observedContext!=null) json="{\"observed_context\":"+observedContext+","+json.Substring(1);
          Append(json);
        }
        // Append/checkpoint precede deletion; restart deduplicates a surviving queue.
        File.Delete(path);
      } finally { Array.Clear(plain,0,plain.Length); }
    }
  }

  static byte[] Join(params byte[][] parts) {
    int size = 0; foreach (byte[] p in parts) size = checked(size + p.Length);
    byte[] result = new byte[size]; int offset = 0;
    foreach (byte[] p in parts) { Buffer.BlockCopy(p, 0, result, offset, p.Length); offset += p.Length; }
    return result;
  }
  static byte[] Slice(byte[] value, int offset, int size) {
    if (offset < 0 || size < 0 || offset + size > value.Length) throw new InvalidDataException("Archivo incompleto.");
    byte[] result = new byte[size]; Buffer.BlockCopy(value, offset, result, 0, size); return result;
  }
  static bool Same(byte[] a, byte[] b) {
    if (a.Length != b.Length) return false;
    int diff = 0; for (int i = 0; i < a.Length; i++) diff |= a[i] ^ b[i]; return diff == 0;
  }
  static byte[] Random(int length) {
    byte[] result = new byte[length]; using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(result); return result;
  }
  static byte[] Derive(string password, byte[] salt) {
    using (Rfc2898DeriveBytes kdf = new Rfc2898DeriveBytes(password, salt, Iterations, HashAlgorithmName.SHA256)) return kdf.GetBytes(64);
  }
  static byte[] Mac(byte[] keys, byte[] data) {
    using (HMACSHA256 hmac = new HMACSHA256(Slice(keys, 32, 32))) return hmac.ComputeHash(data);
  }
  static byte[] Crypt(byte[] keys, byte[] iv, byte[] data, bool encrypt) {
    using (Aes aes = Aes.Create()) {
      aes.Key = Slice(keys, 0, 32); aes.IV = iv; aes.Mode = CipherMode.CBC; aes.Padding = PaddingMode.PKCS7;
      using (ICryptoTransform transform = encrypt ? aes.CreateEncryptor() : aes.CreateDecryptor()) return transform.TransformFinalBlock(data, 0, data.Length);
    }
  }
  static void Atomic(string path, byte[] data) {
    string temp = path + ".tmp-" + Guid.NewGuid().ToString("N");
    try {
      using (FileStream f = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { f.Write(data,0,data.Length); f.Flush(true); }
      if (File.Exists(path)) File.Replace(temp,path,null); else File.Move(temp,path);
    } finally { if (File.Exists(temp)) File.Delete(temp); }
  }
  static byte[] ReadExact(Stream stream, int size) {
    byte[] result = new byte[size]; int read = 0;
    while (read < size) { int n = stream.Read(result,read,size-read); if (n == 0) throw new InvalidDataException("Historial incompleto o truncado."); read += n; }
    return result;
  }
  static byte[] ReadHeader(Stream stream) {
    byte[] magic=ReadExact(stream,8);
    if (Same(magic,Magic)) {
      byte[] h=Join(magic,ReadExact(stream,68));
      if (BitConverter.ToInt32(h,40)!=Iterations) throw new InvalidDataException("Formato de historial no admitido.");
      return h;
    }
    if (Same(magic,PublicMagic)) {
      byte[] info=ReadExact(stream,36); int wrappedLength=BitConverter.ToInt32(info,32);
      if (wrappedLength!=384) throw new InvalidDataException("Clave publica de historial invalida.");
      return Join(magic,info,ReadExact(stream,wrappedLength+32));
    }
    throw new InvalidDataException("Formato de historial no admitido.");
  }
  static void AuthenticateHeader(byte[] header, byte[] keys) {
    if (!Same(Mac(keys,Slice(header,0,header.Length-32)),Slice(header,header.Length-32,32))) throw new CryptographicException("Contrasena incorrecta o historial alterado.");
  }
  void SaveState() {
    byte[] plain = Join(header,keys,BitConverter.GetBytes(sequence),previous);
    try { Atomic(statePath, ProtectedData.Protect(plain,Entropy,DataProtectionScope.CurrentUser)); }
    finally { Array.Clear(plain,0,plain.Length); }
  }
  static byte[] ReadRecord(Stream stream, byte[] keys, byte[] previous, long sequence, bool decrypt) {
    int length = BitConverter.ToInt32(ReadExact(stream,4),0);
    if (length < 64 || length > 16777216) throw new InvalidDataException("Registro alterado.");
    byte[] record = ReadExact(stream,length);
    byte[] payload = Slice(record,0,length-32), tag = Slice(record,length-32,32);
    if (BitConverter.ToInt64(payload,0) != sequence || !Same(Mac(keys,Join(previous,payload)),tag)) throw new CryptographicException("Historial alterado: firma o secuencia incorrecta.");
    if (decrypt) return Join(tag,Crypt(keys,Slice(payload,8,16),Slice(payload,24,payload.Length-24),false));
    return tag;
  }
  public static void Setup(string directory, string password) {
    if (String.IsNullOrEmpty(password) || password.Length < 12) throw new ArgumentException("Usa una contrasena de al menos 12 caracteres.");
    Directory.CreateDirectory(directory);
    string path = Path.Combine(directory,"historial.sebilog");
    string state = Path.Combine(directory,"historial.key");
    if (File.Exists(state)) throw new IOException("El historial ya tiene una clave. No se reemplaza.");
    if (File.Exists(path)) {
      // Password recovery on another Windows account: verify every record first.
      using (FileStream f = File.OpenRead(path)) {
        byte[] h = ReadHeader(f), k = Derive(password,Slice(h,8,32));
        try {
          AuthenticateHeader(h,k); byte[] last = Slice(h,44,32); long count = 0;
          while (f.Position < f.Length) last = ReadRecord(f,k,last,++count,false);
          using (SebiHistoryVault v = new SebiHistoryVault()) { v.header=h; v.keys=k; v.previous=last; v.sequence=count; v.statePath=state; v.SaveState(); }
        } finally { Array.Clear(k,0,k.Length); }
      }
      return;
    }
    byte[] baseHeader = Join(Magic,Random(32),BitConverter.GetBytes(Iterations));
    byte[] derived = Derive(password,Slice(baseHeader,8,32));
    try {
      byte[] h = Join(baseHeader,Mac(derived,baseHeader));
      Atomic(path,h);
      using (SebiHistoryVault v = new SebiHistoryVault()) { v.header=h; v.keys=derived; v.previous=Slice(h,44,32); v.sequence=0; v.statePath=state; v.SaveState(); }
    } finally { Array.Clear(derived,0,derived.Length); }
  }
  public static SebiHistoryVault OpenWriter(string directory) {
    SebiHistoryVault v = new SebiHistoryVault();
    v.journal = Path.Combine(directory,"historial.sebilog"); v.statePath = Path.Combine(directory,"historial.key");
    byte[] state = ProtectedData.Unprotect(File.ReadAllBytes(v.statePath),Entropy,DataProtectionScope.CurrentUser);
    try {
      int headerLength=state.Length-104;
      if (headerLength!=76 && headerLength!=460) throw new InvalidDataException("Clave local invalida.");
      v.header=Slice(state,0,headerLength); v.keys=Slice(state,headerLength,64);
      long savedSequence=BitConverter.ToInt64(state,headerLength+64); byte[] savedTag=Slice(state,headerLength+72,32);
      v.file=new FileStream(v.journal,FileMode.Open,FileAccess.ReadWrite,FileShare.Read);
      byte[] diskHeader=ReadHeader(v.file);
      if (!Same(v.header,diskHeader)) throw new CryptographicException("El historial ha sido sustituido.");
      AuthenticateHeader(v.header,v.keys); v.previous=Slice(v.header,v.header.Length-32,32);
      byte[] atCheckpoint = savedSequence == 0 ? v.previous : null;
      while (v.file.Position < v.file.Length) {
        byte[] record=ReadRecord(v.file,v.keys,v.previous,++v.sequence,true);
        try {
          v.previous=Slice(record,0,32);
          string nativeId=NativeId(Utf8.GetString(record,32,record.Length-32));
          if (nativeId!=null) v.nativeEvents.Add(nativeId);
        } finally { Array.Clear(record,0,record.Length); }
        if (v.sequence == savedSequence) atCheckpoint=v.previous;
      }
      // One completed append may survive a crash before the atomic checkpoint.
      if (v.sequence < savedSequence || v.sequence > savedSequence+1 || atCheckpoint==null || !Same(savedTag,atCheckpoint)) throw new CryptographicException("Se han eliminado o sustituido registros.");
      if (v.sequence != savedSequence) v.SaveState();
      return v;
    } catch { v.Dispose(); throw; }
    finally { Array.Clear(state,0,state.Length); }
  }
  public void Append(string json) {
    if (String.IsNullOrEmpty(json) || json.Length > 8000000) throw new InvalidDataException("Registro invalido.");
    byte[] plain=Utf8.GetBytes(json), iv=Random(16);
    try {
      byte[] payload=Join(BitConverter.GetBytes(sequence+1),iv,Crypt(keys,iv,plain,true));
      byte[] tag=Mac(keys,Join(previous,payload)), record=Join(payload,tag);
      byte[] bytes=Join(BitConverter.GetBytes(record.Length),record);
      file.Write(bytes,0,bytes.Length); file.Flush(true);
      sequence++; previous=tag; SaveState();
      string nativeId=NativeId(json); if (nativeId!=null) nativeEvents.Add(nativeId);
    } finally { Array.Clear(plain,0,plain.Length); }
  }
  public static string Read(string directory, string password) {
    return ReadFile(Path.Combine(directory,"historial.sebilog"),null,password);
  }
  public static string ReadFile(string historyFile, string adminFile, string password) {
    using (FileStream f = new FileStream(historyFile,FileMode.Open,FileAccess.Read,FileShare.ReadWrite)) {
      byte[] header=ReadHeader(f), keys;
      if (Same(Slice(header,0,8),PublicMagic)) {
        if (String.IsNullOrEmpty(adminFile)) throw new CryptographicException("Se necesita la clave privada del administrador.");
        using (RSACryptoServiceProvider rsa=LoadAdmin(adminFile,password)) {
          if (!Same(Fingerprint(rsa.ToXmlString(false)),Slice(header,8,32))) throw new CryptographicException("Este historial pertenece a otra clave de administrador.");
          keys=rsa.Decrypt(Slice(header,44,384),RSAEncryptionPadding.OaepSHA1);
        }
        if (keys.Length!=64) throw new CryptographicException("Clave de historial invalida.");
      } else { keys=Derive(password,Slice(header,8,32)); }
      try {
        AuthenticateHeader(header,keys); byte[] previous=Slice(header,header.Length-32,32); long sequence=0;
        StringBuilder text=new StringBuilder();
        while (f.Position < f.Length) {
          byte[] data=ReadRecord(f,keys,previous,++sequence,true);
          previous=Slice(data,0,32); text.Append(Utf8.GetString(data,32,data.Length-32)).Append(Environment.NewLine);
          Array.Clear(data,0,data.Length);
        }
        // A copied journal can be read with its password; local checkpoint also
        // detects removal of complete trailing records on the original account.
        string statePath=Path.ChangeExtension(historyFile,".key");
        if (File.Exists(statePath)) {
          byte[] state=null;
          try { state=ProtectedData.Unprotect(File.ReadAllBytes(statePath),Entropy,DataProtectionScope.CurrentUser); }
          catch (CryptographicException) { /* Another Windows account; password verification still applies. */ }
          if (state!=null) {
            try {
              int h=header.Length;
              if (state.Length!=h+104 || !Same(header,Slice(state,0,h)) || BitConverter.ToInt64(state,h+64)>sequence ||
                  (BitConverter.ToInt64(state,h+64)==sequence && !Same(previous,Slice(state,h+72,32)))) throw new CryptographicException("Historial truncado o sustituido.");
            } finally { Array.Clear(state,0,state.Length); }
          }
        }
        return text.ToString();
      } finally { Array.Clear(keys,0,keys.Length); }
    }
  }
  static byte[] Fingerprint(string publicXml) {
    using (SHA256 sha=SHA256.Create()) return sha.ComputeHash(Utf8.GetBytes(publicXml));
  }
  static RSACryptoServiceProvider NewRsa() {
    RSACryptoServiceProvider rsa=new RSACryptoServiceProvider(3072); rsa.PersistKeyInCsp=false; return rsa;
  }
  public static void CreateAdmin(string keyFile, string password, string publicFile) {
    if (String.IsNullOrEmpty(password) || password.Length<12) throw new ArgumentException("Contrasena demasiado corta.");
    if (File.Exists(keyFile) || File.Exists(publicFile)) throw new IOException("Ya existe una clave. No se genera otra ni se reemplaza.");
    Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(keyFile)));
    using (RSACryptoServiceProvider rsa=NewRsa()) {
      Atomic(keyFile,ProtectAdmin(rsa,password));
      Atomic(publicFile,Utf8.GetBytes(rsa.ToXmlString(false)));
    }
  }
  static byte[] ProtectAdmin(RSACryptoServiceProvider rsa, string password) {
    byte[] salt=Random(32), keys=Derive(password,salt), iv=Random(16), plain=Utf8.GetBytes(rsa.ToXmlString(true));
    try {
      byte[] encrypted=Crypt(keys,iv,plain,true);
      byte[] payload=Join(AdminMagic,salt,BitConverter.GetBytes(Iterations),iv,BitConverter.GetBytes(encrypted.Length),encrypted);
      return Join(payload,Mac(keys,payload));
    } finally { Array.Clear(keys,0,keys.Length); Array.Clear(plain,0,plain.Length); }
  }
  public static void ReprotectAdmin(string keyFile, string oldPassword, string newPassword) {
    if (String.IsNullOrEmpty(newPassword) || newPassword.Length<12) throw new ArgumentException("Contrasena demasiado corta.");
    string candidate=keyFile+".reprotect-"+Guid.NewGuid().ToString("N");
    try {
      using (RSACryptoServiceProvider original=LoadAdmin(keyFile,oldPassword)) {
        Atomic(candidate,ProtectAdmin(original,newPassword));
        using (RSACryptoServiceProvider verified=LoadAdmin(candidate,newPassword)) {
          if (!Same(Fingerprint(original.ToXmlString(false)),Fingerprint(verified.ToXmlString(false)))) throw new CryptographicException("No se puede cambiar la autoridad del historial.");
        }
        File.Replace(candidate,keyFile,null);
      }
    } finally { if (File.Exists(candidate)) File.Delete(candidate); }
  }
  static RSACryptoServiceProvider LoadAdmin(string keyFile, string password) {
    if (new FileInfo(keyFile).Length>8192) throw new InvalidDataException("Clave privada no valida.");
    byte[] data=File.ReadAllBytes(keyFile);
    if (data.Length<112 || data.Length>8192 || !Same(Slice(data,0,8),AdminMagic) || BitConverter.ToInt32(data,40)!=Iterations || BitConverter.ToInt32(data,60)!=data.Length-96) throw new InvalidDataException("Clave privada no valida.");
    byte[] keys=Derive(password,Slice(data,8,32));
    try {
      if (!Same(Mac(keys,Slice(data,0,data.Length-32)),Slice(data,data.Length-32,32))) throw new CryptographicException("Contrasena incorrecta o clave privada alterada.");
      byte[] plain=Crypt(keys,Slice(data,44,16),Slice(data,64,data.Length-96),false);
      try {
        RSACryptoServiceProvider rsa=NewRsa();
        try { rsa.FromXmlString(Utf8.GetString(plain)); if (rsa.PublicOnly) throw new CryptographicException("Falta la clave privada."); return rsa; }
        catch { rsa.Dispose(); throw; }
      } finally { Array.Clear(plain,0,plain.Length); }
    } finally { Array.Clear(keys,0,keys.Length); }
  }
  public static void SetupPublic(string directory, string publicFile) {
    Directory.CreateDirectory(directory);
    string path=Path.Combine(directory,"historial.sebilog"), state=Path.Combine(directory,"historial.key");
    if (File.Exists(path)) {
      using (FileStream f=File.OpenRead(path)) {
        byte[] h=ReadHeader(f);
        if (!Same(Slice(h,0,8),PublicMagic)) throw new IOException("Historial antiguo: el administrador debe migrarlo antes de continuar.");
        using (RSACryptoServiceProvider rsa=NewRsa()) {
          rsa.FromXmlString(File.ReadAllText(publicFile,Utf8));
          if (!Same(Slice(h,8,32),Fingerprint(rsa.ToXmlString(false)))) throw new CryptographicException("No se cambia la clave publica de un historial existente.");
        }
      }
      if (!File.Exists(state)) throw new IOException("Falta historial.key. Conserva el historial y recupera la clave local con el administrador.");
      return;
    }
    if (File.Exists(state)) throw new IOException("Falta el historial original. No se reemplaza con uno vacio.");
    byte[] keys=Random(64);
    try {
      using (RSACryptoServiceProvider rsa=NewRsa()) {
        rsa.FromXmlString(File.ReadAllText(publicFile,Utf8));
        if (!rsa.PublicOnly || rsa.KeySize!=3072) throw new CryptographicException("El juego debe incluir solo la clave publica de 3072 bits.");
        byte[] wrapped=rsa.Encrypt(keys,RSAEncryptionPadding.OaepSHA1);
        byte[] baseHeader=Join(PublicMagic,Fingerprint(rsa.ToXmlString(false)),BitConverter.GetBytes(wrapped.Length),wrapped);
        byte[] h=Join(baseHeader,Mac(keys,baseHeader));
        Atomic(path,h);
        using (SebiHistoryVault v=new SebiHistoryVault()) { v.header=h; v.keys=keys; v.previous=Slice(h,h.Length-32,32); v.statePath=state; v.SaveState(); }
      }
    } finally { Array.Clear(keys,0,keys.Length); }
  }
  public static void ImportPlainPublic(string directory, string publicFile) {
    string legacy=Path.Combine(directory,"historial.jsonl");
    if (!File.Exists(legacy)) return;
    using (SebiHistoryVault original=OpenWriter(directory)) {
      if (original.sequence!=0) throw new IOException("Historial JSONL pendiente: no se fusiona con otro historial poblado.");
    }
    string stage=Path.Combine(directory,".public-history-migration-"+Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(stage);
    try {
      SetupPublic(stage,publicFile);
      using (SebiHistoryVault writer=OpenWriter(stage))
      using (StreamReader reader=new StreamReader(legacy,Utf8,true)) {
        string line; while ((line=reader.ReadLine())!=null) if (!String.IsNullOrWhiteSpace(line)) writer.Append(line);
      }
      using (SebiHistoryVault verify=OpenWriter(stage)) {}
      Atomic(Path.Combine(directory,"historial.sebilog"),File.ReadAllBytes(Path.Combine(stage,"historial.sebilog")));
      Atomic(Path.Combine(directory,"historial.key"),File.ReadAllBytes(Path.Combine(stage,"historial.key")));
      using (SebiHistoryVault verify=OpenWriter(directory)) {}
      File.Delete(legacy);
    } finally { Directory.Delete(stage,true); }
  }
  public static void Upgrade(string directory, string publicFile, string adminFile, string password) {
    string original=Path.Combine(directory,"historial.sebilog");
    if (!File.Exists(original)) { SetupPublic(directory,publicFile); ImportPlainPublic(directory,publicFile); return; }
    using (FileStream f=File.OpenRead(original)) {
      if (Same(Slice(ReadHeader(f),0,8),PublicMagic)) { ReadFile(original,adminFile,password); return; }
    }
    string clear=Read(directory,password);
    string stage=Path.Combine(directory,".upgrade-history-"+Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(stage);
    try {
      SetupPublic(stage,publicFile);
      using (SebiHistoryVault writer=OpenWriter(stage))
      using (StringReader reader=new StringReader(clear)) {
        string line; while ((line=reader.ReadLine())!=null) if (!String.IsNullOrWhiteSpace(line)) writer.Append(line);
      }
      string verified=ReadFile(Path.Combine(stage,"historial.sebilog"),adminFile,password);
      if (verified!=clear) throw new CryptographicException("La migracion no conserva los eventos.");
      string backup=original+".v1-"+DateTime.UtcNow.ToString("yyyyMMddHHmmss")+".bak";
      File.Copy(original,backup,false);
      string oldKey=Path.Combine(directory,"historial.key");
      if (File.Exists(oldKey)) File.Copy(oldKey,backup+".key",false);
      Atomic(original,File.ReadAllBytes(Path.Combine(stage,"historial.sebilog")));
      Atomic(oldKey,File.ReadAllBytes(Path.Combine(stage,"historial.key")));
      ReadFile(original,adminFile,password);
    } finally { clear=null; Directory.Delete(stage,true); }
  }
  public static void ImportLegacy(string directory, string password) {
    string legacy=Path.Combine(directory,"historial.jsonl"), encrypted=Path.Combine(directory,"historial.sebilog");
    if (!File.Exists(legacy)) return;
    // Never merge silently with an already populated authenticated history.
    if (new FileInfo(encrypted).Length!=76) throw new IOException("Hay un historial antiguo pendiente de importar; se conserva sin modificar.");
    string stage=Path.Combine(directory,".history-migration-"+Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(stage);
    try {
      Setup(stage,password);
      using (SebiHistoryVault writer=OpenWriter(stage))
      using (StreamReader reader=new StreamReader(legacy,Utf8,true)) {
        string line;
        while ((line=reader.ReadLine())!=null) {
          if (String.IsNullOrWhiteSpace(line)) continue;
          writer.Append(line);
        }
      }
      Read(stage,password); // Verify decryptability before removing the clear copy.
      Atomic(encrypted,File.ReadAllBytes(Path.Combine(stage,"historial.sebilog")));
      Atomic(Path.Combine(directory,"historial.key"),File.ReadAllBytes(Path.Combine(stage,"historial.key")));
      Read(directory,password);
      File.Delete(legacy);
    } finally { Directory.Delete(stage,true); }
  }
  public static void Serve(string directory, string pipeName, int parentId) {
    PipeSecurity security=new PipeSecurity(); security.SetAccessRuleProtection(true,false);
    security.AddAccessRule(new PipeAccessRule(WindowsIdentity.GetCurrent().User,PipeAccessRights.FullControl,AccessControlType.Allow));
    using (SebiHistoryVault writer=OpenWriter(directory))
    using (NamedPipeServerStream pipe=new NamedPipeServerStream(pipeName,PipeDirection.InOut,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous,65536,65536,security)) {
      IAsyncResult waiting=pipe.BeginWaitForConnection(null,null);
      while (!waiting.AsyncWaitHandle.WaitOne(500)) {
        if (parentId!=0) { try { if (Process.GetProcessById(parentId).HasExited) return; } catch (ArgumentException) { return; } }
      }
      pipe.EndWaitForConnection(waiting);
      while (pipe.IsConnected) {
        try {
          int size=BitConverter.ToInt32(ReadExact(pipe,4),0);
          if (size<1 || size>8000000) throw new InvalidDataException("Tamano de registro invalido.");
          byte[] bytes=ReadExact(pipe,size);
          try {
            string json=Utf8.GetString(bytes);
            Match eventName=Regex.Match(json,"\"event\"\\s*:\\s*\"([^\"]+)\"");
            bool poll=eventName.Success && eventName.Groups[1].Value=="activity_poll";
            writer.DrainPending(directory,json);
            if (!poll) writer.Append(json);
          }
          finally { Array.Clear(bytes,0,bytes.Length); }
          pipe.WriteByte(1); pipe.Flush();
        } catch (Exception) { try { pipe.WriteByte(0); pipe.Flush(); } catch {} return; }
      }
    }
  }
  public void Dispose() { if (file!=null) file.Dispose(); if (keys!=null) Array.Clear(keys,0,keys.Length); }
}
'@
}
if ($Mode -eq 'Library') { return }
if (!$ConfigDir) { throw 'Falta la carpeta de configuracion del jugador.' }
$ConfigDir = [SebiHistoryVault]::PrepareDirectory($ConfigDir)
if (!$PublicKeyFile) { $PublicKeyFile = Join-Path $PSScriptRoot 'activity-public-key.txt' }
if (!$KeyFile) { $KeyFile = Join-Path $ConfigDir 'historial-admin.sebikey' }

function Read-HistoryPassword {
  if ($UseConsole) { return Read-Host 'Contrasena del historial' -AsSecureString }
  Add-Type -AssemblyName System.Windows.Forms,System.Drawing
  $dialog = New-Object Windows.Forms.Form
  $dialog.Text = 'SebiLink - Contrasena del historial'; $dialog.Size = New-Object Drawing.Size(440,170)
  $dialog.StartPosition = 'CenterScreen'; $dialog.TopMost = $true
  $label = New-Object Windows.Forms.Label; $label.Text = 'Contrasena de la clave privada del administrador:'; $label.SetBounds(15,12,395,24)
  $box = New-Object Windows.Forms.TextBox; $box.UseSystemPasswordChar = $true; $box.SetBounds(15,40,395,25)
  $button = New-Object Windows.Forms.Button; $button.Text = 'Aceptar'; $button.SetBounds(300,80,110,30); $button.DialogResult = 'OK'
  $dialog.Controls.AddRange(@($label,$box,$button)); $dialog.AcceptButton=$button
  try {
    if ($dialog.ShowDialog() -ne 'OK') { throw 'Configuracion/consulta cancelada.' }
    return ConvertTo-SecureString -String $box.Text -AsPlainText -Force
  } finally { $box.Clear(); $dialog.Dispose() }
}
function Invoke-WithHistoryPassword([scriptblock]$Action) {
  $secure = Read-HistoryPassword
  $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { & $Action ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose() }
}
try {
  if ($Mode -in @('Setup','Writer','View')) {
    & (Join-Path $PSScriptRoot 'SebiHistoryViewer.ps1') -Mode Install -ConfigDir $ConfigDir
  }
  if ($Mode -eq 'AdminSetup') {
    Invoke-WithHistoryPassword { param($password)
      [SebiHistoryVault]::CreateAdmin($KeyFile,$password,$PublicKeyFile)
      [SebiHistoryVault]::Upgrade($ConfigDir,$PublicKeyFile,$KeyFile,$password)
    }
    if ($UseConsole) { Write-Output 'PASS: clave administradora creada y protegida; historial universal configurado, sin guardar la contrasena.' }
  } elseif ($Mode -eq 'Setup') {
    [SebiHistoryVault]::SetupPublic($ConfigDir,$PublicKeyFile)
    [SebiHistoryVault]::ImportPlainPublic($ConfigDir,$PublicKeyFile)
    if ($UseConsole) { Write-Output 'PASS: historial universal configurado sin contrasena del jugador.' }
  } elseif ($Mode -eq 'Writer') {
    [SebiHistoryVault]::SetupPublic($ConfigDir,$PublicKeyFile)
    [SebiHistoryVault]::ImportPlainPublic($ConfigDir,$PublicKeyFile)
    [SebiHistoryVault]::Serve($ConfigDir,$PipeName,$ParentId)
  } elseif ($Mode -eq 'View') {
    # WinForms closures must resolve viewer helpers in this entrypoint's scope.
    . (Join-Path $PSScriptRoot 'SebiHistoryViewer.ps1') -Mode View -ConfigDir $ConfigDir -HistoryFile $HistoryFile -KeyFile $KeyFile
  }
} catch {
  $message = $_.Exception.GetBaseException().Message
  if ($UseConsole) { throw $message }
  if ($Mode -eq 'Writer') {
    # Diagnostics contain only error text, never events, keys or passwords.
    [IO.File]::WriteAllText((Join-Path $ConfigDir 'historial-error.txt'),$message)
  } else {
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show($message,'SebiLink - Historial','OK','Error')
  }
}
