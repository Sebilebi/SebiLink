# Pokemon Z updater. Network/download/install run in a hidden PowerShell worker.
# All player runtime files live outside the publishable game/mod directory.
module SebiLinkUpdater
  @boot_checked = false
  @pending = nil
  @busy = false
  @serial = 0
  @restart_pending = false

  def self.game_dir
    return File.expand_path(File.join(File.dirname(__FILE__), ".."))
  end

  def self.version
    text = File.open(File.join(game_dir, "multiplayer/updates/update-source.json"), "rb") { |f| f.read }
    match = text.match(/"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)"/)
    return match ? match[1] : "desconocida"
  rescue StandardError
    return "desconocida"
  end

  def self.runtime_dir
    return SebiLinkPaths.runtime_dir("updates")
  end

  def self.pid
    return SebiBattleSpectator.current_process_id if defined?(SebiBattleSpectator)
    return Win32API.new("kernel32", "GetCurrentProcessId", "", "l").call.to_i
  rescue StandardError
    return 0
  end

  def self.busy?
    return @busy || @restart_pending
  end

  def self.quote(value)
    return '"' + value.to_s.gsub('"', '') + '"'
  end

  def self.launch(mode, id, extra = "")
    args = "-Mode " + mode + " -GameDir " + quote(game_dir) +
      " -RuntimeDir " + quote(runtime_dir) + " -RequestId " + quote(id) + extra
    return SebiSaveManager.open_powershell_script(
      File.join(game_dir, "multiplayer/updates/SebiUpdateWorker.ps1"), args)
  end

  def self.new_id
    @serial += 1
    return pid.to_s + "-" + Time.now.to_i.to_s + "-" + @serial.to_s
  end

  def self.read_result(mode, id)
    path = File.join(runtime_dir, mode.downcase + "-" + id + ".ini")
    return nil if !FileTest.exist?(path)
    values = {}
    File.open(path, "rb") do |f|
      f.each_line do |line|
        key, value = line.gsub(/[\r\n]/, "").split("=", 2)
        values[key] = value if key && value
      end
    end
    return nil if values["request_id"] != id || !values["status"]
    return values
  rescue StandardError
    return nil
  end

  def self.start_check(manual = false)
    return false if busy?
    @boot_checked = true
    if @pending
      @pending[:manual] = true if manual
      return true
    end
    SebiLinkPaths.ensure_dir(runtime_dir)
    id = new_id
    unless launch("Check", id)
      Kernel.pbMessage(_INTL("No se pudo iniciar la busqueda de actualizaciones.")) if manual
      return false
    end
    @pending = { :id => id, :manual => manual, :started => Time.now.to_f }
    return true
  rescue StandardError
    Kernel.pbMessage(_INTL("No se pudo buscar actualizaciones: {1}", $!.message)) if manual
    return false
  end

  def self.loaded_game?
    return defined?(Scene_Map) && $scene.is_a?(Scene_Map) &&
      $Trainer && $PokemonGlobal && $game_map && $game_map.map_id.to_i > 0
  rescue StandardError
    return false
  end

  def self.safe_to_prompt?
    return false if busy? || !$scene
    allowed = loaded_game? || (defined?(Scene_Intro) && $scene.is_a?(Scene_Intro) && !$Trainer)
    return false if !allowed
    if $game_temp
      return false if $game_temp.in_battle || $game_temp.battle_calling ||
        $game_temp.player_transferring || $game_temp.message_window_showing
    end
    return false if loaded_game? && pbMapInterpreterRunning?
    return true
  rescue StandardError
    return false
  end

  def self.wait_result(mode, id, seconds, message)
    window = Kernel.pbCreateMessageWindow
    window.z = 100100
    window.letterbyletter = false
    window.text = message
    deadline = Time.now.to_f + seconds
    loop do
      Graphics.update
      window.update
      result = read_result(mode, id)
      return result if result
      return { "status" => "error", "message" => _INTL("La busqueda/descarga ha tardado demasiado. No se ha actualizado el juego.") } if Time.now.to_f > deadline
    end
  ensure
    Kernel.pbDisposeMessageWindow(window) if window
  end

  def self.check_now
    return false if busy?
    unless safe_to_prompt?
      Kernel.pbMessage(_INTL("Busca actualizaciones desde el mapa, fuera de combates y eventos."))
      return false
    end
    return false unless start_check(true)
    pending = @pending
    @busy = true
    result = wait_result("Check", pending[:id], 60, _INTL("Buscando actualizaciones de SebiLink... Version instalada: {1}", version))
    @pending = nil
    @busy = false
    handle_result(result, true)
    return true
  ensure
    @busy = false
  end

  def self.handle_result(result, manual)
    case result["status"]
    when "current"
      Kernel.pbMessage(_INTL("Tienes la version mas reciente de SebiLink para Pokemon Z ({1}).", version)) if manual
    when "available"
      @busy = true
      accepted = Kernel.pbConfirmMessage(_INTL("Nueva version de SebiLink para Pokemon Z: {1}\nVersion instalada: {2}\nActualizar ahora? Se guardara la partida y se reiniciara el juego.", result["version"], version))
      perform_update(result) if accepted
    else
      Kernel.pbMessage(_INTL("No se pudo comprobar/actualizar SebiLink: {1}", result["message"])) if manual
    end
  ensure
    @busy = false
  end

  def self.perform_update(result)
    return false if result["commit"].to_s !~ /\A[a-f0-9]{40}\z/ || result["version"].to_s !~ /\A[0-9]+\.[0-9]+\.[0-9]+\z/
    # Create the exit API before saving/downloading; never use arbitrary shell code.
    @exit_api = Win32API.new("kernel32", "ExitProcess", "l", "")
    if pid <= 0
      Kernel.pbMessage(_INTL("No se pudo identificar el proceso del juego. No se ha actualizado."))
      return false
    end
    if loaded_game? && !pbSave(false)
      Kernel.pbMessage(_INTL("No se pudo guardar la partida. Se cancela la actualizacion."))
      return false
    end
    id = new_id
    extra = " -Commit " + quote(result["commit"]) + " -ExpectedVersion " + quote(result["version"]) + " -ParentPid " + pid.to_s
    unless launch("Prepare", id, extra)
      Kernel.pbMessage(_INTL("No se pudo iniciar la descarga. El juego sigue abierto."))
      return false
    end
    ready = wait_result("Prepare", id, 600, _INTL("Descargando y verificando SebiLink {1}...\nEl juego se reiniciara al terminar.", result["version"]))
    if ready["status"] != "ready"
      Kernel.pbMessage(_INTL("No se ha actualizado: {1}", ready["message"]))
      return false
    end
    # Authorization file is only written after confirmed consent/save/download.
    File.open(File.join(runtime_dir, "restart-" + id + ".txt"), "wb") { |f| f.write(id) }
    @restart_pending = true
    return true
  rescue StandardError
    Kernel.pbMessage(_INTL("No se ha actualizado: {1}", $!.message))
    return false
  end

  def self.restart
    # The helper waits for this exact game process to exit before replacing files.
    SebiVisualMultiplayer.stop_hosted_server(false) if defined?(SebiVisualMultiplayer)
    @exit_api.call(0)
  end

  def self.update
    return if @busy
    return restart if @restart_pending
    start_check(false) if !@boot_checked
    return if !@pending || !safe_to_prompt?
    result = read_result("Check", @pending[:id])
    if !result && Time.now.to_f - @pending[:started] > 60
      result = { "status" => "error", "message" => _INTL("Sin respuesta de GitHub.") }
    end
    return if !result
    manual = @pending[:manual]
    @pending = nil
    handle_result(result, manual)
  rescue StandardError
    @pending = nil
  end
end

if defined?(Input)
  class << Input
    unless method_defined?(:sebi_updater_input_without_updates)
      alias sebi_updater_input_without_updates update
      def update
        ret = sebi_updater_input_without_updates
        SebiLinkUpdater.update
        return ret
      end
    end
  end
end
