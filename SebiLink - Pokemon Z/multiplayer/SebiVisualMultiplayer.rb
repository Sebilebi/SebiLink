# SebiPokeLink visual-only multiplayer client for Pokemon Z.
# Loaded before Main by the installed loader or portable SebiLinkBootstrap.

if defined?(Socket) && defined?(Winsock) && !Socket.method_defined?(:sebi_recv_once)
  module Winsock
    unless respond_to?(:ioctlsocket)
      def self.ioctlsocket(*args)
        Win32API.new(DLL, "ioctlsocket", "plp", "l").call(*args)
      end
    end

    unless respond_to?(:getsockopt)
      def self.getsockopt(*args)
        Win32API.new(DLL, "getsockopt", "pllpl", "l").call(*args)
      end
    end
  end

  class Socket
    SEBI_FIONBIO = -2147195266

    def sebi_fd
      return instance_variable_get("@fd")
    rescue Exception
      return nil
    end

    def sebi_set_nonblocking(value)
      arg = [value ? 1 : 0].pack("L")
      return Winsock.ioctlsocket(sebi_fd, SEBI_FIONBIO, arg) == 0
    rescue Exception
      return false
    end

    def sebi_socket_error
      error = [0].pack("l")
      length = [4].pack("l")
      ret = Winsock.getsockopt(sebi_fd, Socket::SOL_SOCKET, Socket::SO_ERROR, error, length)
      return Winsock.WSAGetLastError if ret == -1
      return error.unpack("l")[0]
    rescue Exception
      return 0
    end

    def sebi_writable?
      fdset = [1, sebi_fd].pack("ll")
      exceptset = [1, sebi_fd].pack("ll")
      timeout = [0, 0].pack("ll")
      return Winsock.select(1, 0, fdset, exceptset, timeout) > 0
    rescue Exception
      return false
    end

    def sebi_recv_once(len, flags = 0)
      buf = "\0" * len
      retval = Winsock.recv(sebi_fd, buf, buf.size, flags)
      if retval == -1
        error = Winsock.WSAGetLastError rescue 0
        return "" if error == 10035
        return nil
      end
      return nil if retval == nil || retval <= 0
      return buf[0, retval]
    end
  end
end

module SebiLinkPaths
  CONFIG_DIR_NAME = "SebiLinkConfig"

  def self.multiplayer_dir
    return File.dirname(File.expand_path(__FILE__)) rescue "multiplayer"
  end

  def self.env_userprofile
    return ENV["USERPROFILE"] rescue nil
  end

  def self.save_root
    root = nil
    begin
      root = RTP.getSaveFolder if defined?(RTP)
    rescue Exception
      root = nil
    end
    if root == nil || root.to_s.strip == ""
      profile = env_userprofile
      root = File.join(profile, "Saved Games", "Pokemon Z") if profile && profile.to_s.strip != ""
    end
    root = "." if root == nil || root.to_s.strip == ""
    return File.expand_path(root) rescue root
  end

  def self.config_dir
    return File.join(save_root, CONFIG_DIR_NAME)
  rescue Exception
    return CONFIG_DIR_NAME
  end

  def self.config_path(filename)
    return File.join(config_dir, filename.to_s)
  rescue Exception
    return filename.to_s
  end

  def self.runtime_dir(name)
    return File.join(config_dir, name.to_s, "runtime")
  rescue Exception
    return File.join(CONFIG_DIR_NAME, name.to_s, "runtime")
  end

  def self.ensure_dir(path)
    path = path.to_s.gsub("\\", "/")
    return if path == "" || FileTest.directory?(path)
    parts = path.split("/")
    current = ""
    for part in parts
      next if part == ""
      if current == ""
        current = part
        next if part =~ /\A[A-Za-z]:\z/
      else
        current += "/" + part
      end
      Dir.mkdir(current) if !FileTest.directory?(current)
    end
  rescue Exception
  end

  def self.ensure_config_dir
    ensure_dir(config_dir)
  end

  def self.copy_file(old_path, new_path)
    ensure_dir(File.dirname(new_path))
    File.open(old_path, "rb") do |src|
      File.open(new_path, "wb") do |dst|
        loop do
          chunk = src.read(8192)
          break if !chunk || chunk.length == 0
          dst.write(chunk)
        end
      end
    end
  rescue Exception
  end

  def self.migrate_file(old_path, new_path)
    return if old_path == nil || new_path == nil
    same_path = false
    begin
      same_path = File.expand_path(old_path) == File.expand_path(new_path)
    rescue Exception
      same_path = false
    end
    return if same_path
    return if FileTest.exist?(new_path)
    return if !FileTest.exist?(old_path)
    copy_file(old_path, new_path)
  rescue Exception
  end

  def self.copy_dir(old_dir, new_dir)
    ensure_dir(new_dir)
    Dir.foreach(old_dir) do |entry|
      next if entry == "." || entry == ".."
      old_path = File.join(old_dir, entry)
      new_path = File.join(new_dir, entry)
      if FileTest.directory?(old_path)
        copy_dir(old_path, new_path)
      elsif !FileTest.exist?(new_path)
        copy_file(old_path, new_path)
      end
    end
  rescue Exception
  end

  def self.migrate_runtime_dir(old_dir, new_dir)
    return if old_dir == nil || new_dir == nil
    same_path = false
    begin
      same_path = File.expand_path(old_dir) == File.expand_path(new_dir)
    rescue Exception
      same_path = false
    end
    return if same_path
    return if FileTest.directory?(new_dir)
    return if !FileTest.directory?(old_dir)
    copy_dir(old_dir, new_dir)
  rescue Exception
  end
end

module SebiLinkFileConfig
  BASE_DIR = SebiLinkPaths.config_dir rescue "SebiLinkConfig"
  PATH = SebiLinkPaths.config_path("sebilink.ini") rescue "SebiLinkConfig/sebilink.ini"
  LEGACY_PATH = File.join(SebiLinkPaths.multiplayer_dir, "sebilink.ini") rescue "multiplayer/sebilink.ini"
  @values = nil
  @revision = 0

  def self.read_values(path)
    result = {}
    return result if !FileTest.exist?(path)
    File.open(path, "rb") do |file|
      file.each_line do |line|
        line = line.sub(/\A\357\273\277/, "").strip
        next if line == "" || line =~ /\A[#;\[]/
        pair = line.split("=", 2)
        next if pair.length < 2
        result[pair[0].strip.downcase] = pair[1].strip
      end
    end
    return result
  end

  def self.load
    SebiLinkPaths.migrate_file(LEGACY_PATH, PATH) if defined?(SebiLinkPaths)
    @values = read_values(PATH)
    @revision = @revision.to_i + 1
    # Import the old network file once; existing unified keys always win.
    [SebiLinkPaths.config_path("multiplayer.ini"), File.join(SebiLinkPaths.multiplayer_dir, "multiplayer.ini")].each do |path|
      read_values(path).each do |key, value|
        target = key == "name" ? "player_name" : "multiplayer_" + key
        @values[target] = value if !@values.has_key?(target)
      end
    end if !@values.has_key?("config_unified_version")
  rescue Exception
    @values = {}
  end

  def self.values
    load if !@values
    return @values
  end

  def self.get(key, default_value = nil)
    value = values[key.to_s.downcase]
    return default_value if value == nil || value == ""
    return value
  end

  def self.has_key?(key)
    return values.has_key?(key.to_s.downcase)
  rescue Exception
    return false
  end

  def self.get_int(key, default_value)
    value = get(key, nil)
    return default_value if value == nil || value == ""
    return value.to_i
  rescue Exception
    return default_value
  end

  def self.get_bool(key, default_value)
    value = get(key, nil)
    return default_value if value == nil || value == ""
    value = value.to_s.downcase
    return true if value == "true" || value == "1" || value == "yes" || value == "on" || value == "si"
    return false if value == "false" || value == "0" || value == "no" || value == "off"
    return default_value
  end

  def self.set(key, value)
    return set_many({key.to_s.downcase => value})
  end

  def self.set_many(changes)
    ensure_dir
    # Both the game and native windows use this short-lived shared lock.
    lock_path = PATH + ".lock"
    deadline = Time.now + 2
    lock = nil
    begin
      begin
        lock = File.open(lock_path, File::WRONLY | File::CREAT | File::EXCL)
      rescue Errno::EEXIST
        begin
          File.delete(lock_path) if Time.now - File.mtime(lock_path) > 30
        rescue Errno::ENOENT
          # Another writer just released the lock; try again.
        end
        raise "No se pudo bloquear sebilink.ini" if Time.now >= deadline
        sleep(0.02)
        retry
      end
      merged = values.merge(read_values(PATH))
      if !changes.has_key?("config_seeded_keys")
        seeded = merged["config_seeded_keys"].to_s.split(",")
        changes.keys.each { |key| seeded.delete(key.to_s.downcase) }
        merged["config_seeded_keys"] = seeded.sort.join(",")
      end
      changes.each do |key, value|
        name = key.to_s.downcase
        raise "Clave INI invalida" if name !~ /\A[a-z0-9_]+\z/
        merged[name] = value == nil ? "" : value.to_s.gsub(/[\r\n]/, " ")
      end
      merged["config_unified_version"] = "1"
      tmp = PATH + ".tmp"
      File.open(tmp, "wb") do |file|
        file.write("# SebiLink player settings.\n")
        file.write("# control_0..15: Abajo, Izquierda, Derecha, Arriba, Aceptar C, Aceptar Enter, Cancelar X, Cancelar Esc, Correr, Turbo, Objeto, Pag abajo, Pag arriba, Curar, Vuelo, Radar.\n")
        file.write("# randomizer_regions: 1 Kanto, 2 Johto, 3 Hoenn, 4 Sinnoh, 5 Teselia, 6 Kalos, 7 Alola, 8 Galar/Hisui, 9 Paldea.\n")
        merged.keys.sort.each { |key| file.write(key + "=" + merged[key] + "\n") }
      end
      # Windows rename does not replace an existing file. MoveFileEx is atomic.
      if defined?(Win32API)
        move = Win32API.new("kernel32", "MoveFileExA", "PPL", "L")
        raise "No se pudo escribir sebilink.ini" if move.call(tmp, PATH, 9) == 0
      else
        File.rename(tmp, PATH)
      end
      @values = merged
      @revision += 1
      return true
    ensure
      lock.close if lock
      File.delete(lock_path) if lock && FileTest.exist?(lock_path)
    end
  end

  def self.option_data(ivar, defaults)
    @option_cache ||= {}
    cached = @option_cache[ivar]
    return cached[1] if cached && cached[0] == @revision && (cached[2] || !$PokemonGlobal)
    legacy = $PokemonGlobal ? $PokemonGlobal.instance_variable_get(ivar) : nil
    legacy = {} if !legacy.is_a?(Hash)
    result = {}
    missing = {}
    defaults.each do |key, default_value|
      if has_key?(key) && !(legacy.has_key?(key) && needs_migration?(key))
        result[key] = default_value == true || default_value == false ? get_bool(key, default_value) :
          (default_value == nil ? (get(key, "").to_s == "" ? nil : get_int(key, 0)) : get_int(key, default_value))
      else
        result[key] = legacy.has_key?(key) ? legacy[key] : default_value
        missing[key] = result[key]
      end
    end
    set_many(missing) if !missing.empty? && $PokemonGlobal
    if $PokemonGlobal && $PokemonGlobal.instance_variable_defined?(ivar)
      $PokemonGlobal.send(:remove_instance_variable, ivar)
    end
    @option_cache[ivar] = [@revision, result, $PokemonGlobal != nil]
    return result
  end

  def self.ensure_dir
    if defined?(SebiLinkPaths)
      SebiLinkPaths.ensure_config_dir
    else
      Dir.mkdir(BASE_DIR) if !FileTest.directory?(BASE_DIR)
    end
  rescue Exception
  end

  def self.save
    return set_many(values)
  end

  def self.needs_migration?(key)
    key = key.to_s
    return true if !has_key?(key)
    return false if !defined?(SebiSettingsRegistry)
    return false if !get("config_seeded_keys", "").split(",").include?(key)
    original = SebiSettingsRegistry.defaults[key]
    return values[key].to_s == original.to_s
  end

  def self.fill_defaults(defaults)
    missing = {}
    defaults.each { |key, value| missing[key] = value if !has_key?(key) }
    return false if missing.empty?
    seeded = get("config_seeded_keys", "").split(",")
    missing["config_seeded_keys"] = (seeded + missing.keys).uniq.sort.join(",")
    set_many(missing)
    return true
  end
end

class SebiRemotePlayer < Game_Character
  attr_reader :remote_id
  attr_reader :remote_name
  attr_reader :remote_map_id
  attr_reader :last_seen
  attr_reader :followers
  attr_reader :busy_state

  def initialize(remote_id, map = nil)
    super(map)
    @remote_id = remote_id
    @remote_name = "Player"
    @remote_map_id = 0
    @through = true
    @transparent = true
    @move_speed = 4.8
    @base_opacity = 220
    @opacity = @base_opacity
    @target_real_x = 0
    @target_real_y = 0
    @followers = []
    @busy_state = "map"
    @last_seen = nil
  end

  def sebi_set_map(map)
    @map = map
  end

  def name
    return "SebiRemotePlayer"
  end

  def receive_packet(name, map_id, x, y, real_x, real_y, direction, pattern, character_name, hue, opacity)
    @remote_name = name.to_s
    @remote_map_id = map_id.to_i
    @x = x.to_i
    @y = y.to_i
    @target_real_x = real_x.to_i
    @target_real_y = real_y.to_i
    if !@last_seen || (@target_real_x - @real_x).abs > Game_Map.realResX * 3 ||
       (@target_real_y - @real_y).abs > Game_Map.realResY * 3
      @real_x = @target_real_x
      @real_y = @target_real_y
    end
    @direction = direction.to_i
    @direction = 2 if @direction != 2 && @direction != 4 && @direction != 6 && @direction != 8
    @pattern = pattern.to_i
    @pattern = 0 if @pattern < 0 || @pattern > 3
    @character_name = character_name.to_s
    @character_hue = hue.to_i
    @base_opacity = opacity.to_i
    @base_opacity = 220 if @base_opacity <= 0 || @base_opacity > 255
    @opacity = @base_opacity
    @transparent = (@character_name == "")
    @last_seen = Graphics.frame_count
  end

  def receive_state(state)
    value = state.to_s
    value = "map" if value == ""
    value = "map" if value != "map" && value != "menu" && value != "battle" && value != "busy"
    @busy_state = value
  rescue Exception
    @busy_state = "map"
  end

  def busy?
    return @busy_state != nil && @busy_state != "" && @busy_state != "map"
  rescue Exception
    return false
  end

  def receive_followers(entries)
    @followers = [] if !@followers
    keep = []
    for i in 0...entries.length
      follower = @followers[i]
      if !follower
        follower = SebiRemoteFollower.new(@remote_id + "_f" + i.to_s, self.map)
        @followers[i] = follower
      end
      data = entries[i]
      follower.receive_packet(@remote_name, data[0], data[1], data[2], data[3],
        data[4], data[5], data[6], data[7], data[8], data[9])
      keep.push(follower)
    end
    @followers = keep
  end

  def remote_characters_for_map(map_id)
    ret = []
    ret.push(self) if @remote_map_id == map_id
    for follower in @followers
      ret.push(follower) if follower.remote_map_id == map_id
    end
    return ret
  end

  def update
    fade_after = SebiVisualMultiplayer.config_number("fade_after", 180)
    hide_after = SebiVisualMultiplayer.config_number("hide_after", 600)
    age = @last_seen ? Graphics.frame_count - @last_seen : hide_after + 1
    @transparent = true if age > hide_after || @character_name == ""
    if age > fade_after
      fade = (age - fade_after) * 2
      @opacity = [80, @base_opacity - fade].max
    else
      @opacity = @base_opacity
    end
    smooth_to_target
  end

  def smooth_to_target
    smoothing = SebiVisualMultiplayer.config_number("remote_smoothing", 2)
    smoothing = 1 if smoothing < 1
    dx = @target_real_x - @real_x
    dy = @target_real_y - @real_y
    if dx != 0
      step = dx / smoothing
      step = 1 if step == 0 && dx > 0
      step = -1 if step == 0 && dx < 0
      @real_x += step
    end
    if dy != 0
      step = dy / smoothing
      step = 1 if step == 0 && dy > 0
      step = -1 if step == 0 && dy < 0
      @real_y += step
    end
  end
end

class SebiRemoteFollower < SebiRemotePlayer
  def receive_packet(name, map_id, x, y, real_x, real_y, direction, pattern, character_name, hue, opacity)
    super(name, map_id, x, y, real_x, real_y, direction, pattern, character_name, hue, opacity)
    @through = true
  end
end

class SebiRemotePlayerLayer
  STATUS_ICON_SIZE = 32

  def initialize(viewport, map)
    @viewport = viewport
    @map = map
    @sprites = {}
    @status_sprites = {}
    @disposed = false
  end

  def disposed?
    return @disposed
  end

  def dispose
    return if @disposed
    for id in @sprites.keys
      @sprites[id].dispose if @sprites[id] && !@sprites[id].disposed?
    end
    for id in @status_sprites.keys
      dispose_status_sprite(@status_sprites[id])
    end
    @sprites.clear
    @status_sprites.clear
    @disposed = true
  end

  def dispose_status_sprite(sprite)
    return if !sprite
    begin
      sprite.bitmap.dispose if sprite.bitmap && !sprite.bitmap.disposed?
    rescue Exception
    end
    begin
      sprite.dispose if !sprite.disposed?
    rescue Exception
    end
  end

  def ensure_status_sprite(id)
    sprite = @status_sprites[id]
    if !sprite || sprite.disposed?
      sprite = Sprite.new(@viewport)
      sprite.bitmap = Bitmap.new(STATUS_ICON_SIZE, STATUS_ICON_SIZE)
      sprite.visible = false
      sprite.z = 99999
      @status_sprites[id] = sprite
    else
      needs_bitmap = false
      begin
        needs_bitmap = true if !sprite.bitmap || sprite.bitmap.disposed?
        needs_bitmap = true if sprite.bitmap.width != STATUS_ICON_SIZE || sprite.bitmap.height != STATUS_ICON_SIZE
      rescue Exception
        needs_bitmap = true
      end
      if needs_bitmap
        begin
          sprite.bitmap.dispose if sprite.bitmap && !sprite.bitmap.disposed?
        rescue Exception
        end
        sprite.bitmap = Bitmap.new(STATUS_ICON_SIZE, STATUS_ICON_SIZE)
        sprite.instance_variable_set("@sebi_busy_state", nil)
      end
    end
    return sprite
  end

  def draw_status_badge(bitmap, back, edge)
    shadow = Color.new(42, 42, 42)
    shadow_rows = [[6, 11, 23], [7, 8, 26], [8, 6, 28], [9, 5, 29], [10, 4, 30], [11, 4, 30], [12, 3, 31], [13, 3, 31], [14, 3, 31], [15, 3, 31], [16, 3, 31], [17, 3, 31], [18, 4, 30], [19, 4, 30], [20, 5, 29], [21, 6, 28], [22, 8, 26], [23, 11, 23]]
    for row in shadow_rows
      bitmap.fill_rect(row[1], row[0], row[2] - row[1] + 1, 1, shadow)
    end
    outline_rows = [[3, 12, 20], [4, 9, 23], [5, 7, 25], [6, 6, 26], [7, 5, 27], [8, 4, 28], [9, 4, 28], [10, 3, 29], [11, 3, 29], [12, 3, 29], [13, 3, 29], [14, 3, 29], [15, 3, 29], [16, 4, 28], [17, 4, 28], [18, 5, 27], [19, 6, 26], [20, 7, 25], [21, 9, 23], [22, 12, 20]]
    for row in outline_rows
      bitmap.fill_rect(row[1], row[0], row[2] - row[1] + 1, 1, edge)
    end
    inner_rows = [[5, 12, 20], [6, 9, 23], [7, 7, 25], [8, 6, 26], [9, 5, 27], [10, 5, 27], [11, 4, 28], [12, 4, 28], [13, 4, 28], [14, 4, 28], [15, 4, 28], [16, 5, 27], [17, 5, 27], [18, 6, 26], [19, 7, 25], [20, 9, 23]]
    for row in inner_rows
      bitmap.fill_rect(row[1], row[0], row[2] - row[1] + 1, 1, back)
    end
    bitmap.fill_rect(10, 6, 7, 1, Color.new(255, 255, 255))
    bitmap.fill_rect(9, 7, 4, 1, Color.new(255, 255, 255))
  rescue Exception
  end

  def draw_menu_status_icon(bitmap)
    dark = Color.new(28, 44, 70)
    paper = Color.new(247, 250, 255)
    line = Color.new(62, 128, 220)
    bitmap.fill_rect(13, 7, 6, 2, dark)
    bitmap.fill_rect(14, 6, 4, 2, paper)
    bitmap.fill_rect(10, 9, 13, 15, dark)
    bitmap.fill_rect(11, 10, 11, 13, paper)
    bitmap.fill_rect(12, 12, 9, 2, line)
    bitmap.fill_rect(12, 16, 8, 1, dark)
    bitmap.fill_rect(12, 19, 8, 1, dark)
    bitmap.fill_rect(12, 22, 6, 1, dark)
  rescue Exception
  end

  def draw_battle_status_icon(bitmap)
    dark = Color.new(24, 24, 24)
    red = Color.new(232, 54, 48)
    white = Color.new(250, 250, 244)
    button = Color.new(232, 232, 226)
    bitmap.fill_rect(13, 8, 7, 1, dark)
    bitmap.fill_rect(11, 9, 11, 1, dark)
    bitmap.fill_rect(10, 10, 13, 2, dark)
    bitmap.fill_rect(9, 12, 15, 7, dark)
    bitmap.fill_rect(10, 19, 13, 2, dark)
    bitmap.fill_rect(11, 21, 11, 1, dark)
    bitmap.fill_rect(13, 22, 7, 1, dark)
    bitmap.fill_rect(13, 9, 7, 1, red)
    bitmap.fill_rect(11, 10, 11, 2, red)
    bitmap.fill_rect(10, 12, 13, 3, red)
    bitmap.fill_rect(10, 16, 13, 3, white)
    bitmap.fill_rect(11, 19, 11, 1, white)
    bitmap.fill_rect(13, 20, 7, 1, white)
    bitmap.fill_rect(9, 15, 15, 2, dark)
    bitmap.fill_rect(14, 13, 5, 5, dark)
    bitmap.fill_rect(15, 14, 3, 3, button)
    bitmap.fill_rect(16, 15, 1, 1, white)
  rescue Exception
  end

  def draw_busy_status_icon(bitmap)
    dark = Color.new(70, 52, 16)
    white = Color.new(255, 250, 224)
    sand = Color.new(244, 206, 88)
    bitmap.fill_rect(11, 8, 11, 2, dark)
    bitmap.fill_rect(12, 10, 9, 1, white)
    bitmap.fill_rect(13, 11, 7, 2, sand)
    bitmap.fill_rect(14, 13, 5, 2, white)
    bitmap.fill_rect(15, 15, 3, 2, dark)
    bitmap.fill_rect(14, 17, 5, 2, white)
    bitmap.fill_rect(13, 19, 7, 2, sand)
    bitmap.fill_rect(12, 21, 9, 1, white)
    bitmap.fill_rect(11, 22, 11, 2, dark)
  rescue Exception
  end

  def redraw_status_sprite(sprite, state)
    return if !sprite || !sprite.bitmap
    old_state = sprite.instance_variable_get("@sebi_busy_state") rescue nil
    return if old_state == state
    sprite.instance_variable_set("@sebi_busy_state", state)
    bitmap = sprite.bitmap
    bitmap.clear
    return if state == nil || state == "" || state == "map"
    if state == "battle"
      back = Color.new(210, 58, 54)
      edge = Color.new(92, 24, 24)
      draw_status_badge(bitmap, back, edge)
      draw_battle_status_icon(bitmap)
    elsif state == "menu"
      back = Color.new(58, 122, 214)
      edge = Color.new(24, 54, 92)
      draw_status_badge(bitmap, back, edge)
      draw_menu_status_icon(bitmap)
    else
      back = Color.new(230, 178, 44)
      edge = Color.new(96, 70, 18)
      draw_status_badge(bitmap, back, edge)
      draw_busy_status_icon(bitmap)
    end
  rescue Exception
  end

  def update_status_sprite(player)
    return if !player
    state = player.respond_to?(:busy_state) ? player.busy_state.to_s : "map"
    if player.is_a?(SebiRemoteFollower) || state == "" || state == "map"
      sprite = @status_sprites[player.remote_id]
      sprite.visible = false if sprite && !sprite.disposed?
      return
    end
    sprite = ensure_status_sprite(player.remote_id)
    redraw_status_sprite(sprite, state)
    sprite.x = player.screen_x - (STATUS_ICON_SIZE / 2)
    sprite.y = player.screen_y - 76
    sprite.z = player.screen_z + 120
    sprite.visible = !player.transparent
  rescue Exception
  end

  def update
    return if @disposed
    players = SebiVisualMultiplayer.characters_for_map(@map.map_id)
    keep = {}
    for player in players
      next if player.character_name == nil || player.character_name == ""
      player.sebi_set_map(@map)
      player.update
      keep[player.remote_id] = true
      if !@sprites[player.remote_id] || @sprites[player.remote_id].disposed?
        begin
          @sprites[player.remote_id] = Sprite_Character.new(@viewport, player)
        rescue Exception
          SebiVisualMultiplayer.log("remote sprite failed: " + $!.class.to_s + ": " + $!.message.to_s)
          next
        end
      else
        @sprites[player.remote_id].update
      end
      update_status_sprite(player)
    end
    for id in @sprites.keys
      next if keep[id]
      @sprites[id].dispose if @sprites[id] && !@sprites[id].disposed?
      @sprites.delete(id)
      dispose_status_sprite(@status_sprites[id])
      @status_sprites.delete(id)
    end
  end
end

class SebiMultiplayerClient
  def initialize
    @socket = nil
    @buffer = ""
    @client_id = nil
    @next_retry_frame = 0
    @last_send_frame = 0
    @connecting = false
    @connect_thread = nil
    @connect_token = 0
    @pending_socket = nil
    @connect_socket = nil
    @connect_deadline_frame = 0
    @connect_error = nil
  end

  def connected?
    return @socket != nil
  end

  def client_id
    return @client_id
  end

  def update
    return if !SebiVisualMultiplayer.enabled?
    connect_if_needed
    return if !@socket
    read_available
    send_position_if_needed
  rescue Exception
    SebiVisualMultiplayer.log("client update failed: " + $!.class.to_s + ": " + $!.message.to_s)
    disconnect
  end

  def connect_if_needed
    return if @socket
    finish_async_connect if @connecting || @pending_socket || @connect_error
    return if @socket || @connecting
    return if Graphics.frame_count < @next_retry_frame
    host = SebiVisualMultiplayer.config_string("host", "127.0.0.1")
    port = SebiVisualMultiplayer.config_number("port", 54545)
    begin_async_connect(host, port)
  rescue Exception
    @socket = nil
    retry_frames = SebiVisualMultiplayer.config_number("retry_frames", 600)
    @next_retry_frame = Graphics.frame_count + retry_frames
    SebiVisualMultiplayer.log("connect failed: " + $!.class.to_s + ": " + $!.message.to_s)
  end

  def begin_async_connect(host, port)
    @connect_token += 1
    token = @connect_token
    @connecting = true
    @pending_socket = nil
    @connect_socket = nil
    @connect_error = nil
    @connect_host = host
    @connect_port = port.to_i
    if defined?(Socket) && defined?(Winsock) && Socket.method_defined?(:sebi_set_nonblocking)
      begin_nonblocking_connect(host, port, token)
    else
      begin_thread_connect(host, port, token)
    end
  rescue Exception
    @connecting = false
    @connect_error = [@connect_token, $!.class.to_s + ": " + $!.message.to_s]
  end

  def begin_thread_connect(host, port, token)
    @connect_thread = Thread.new do
      begin
        socket = TCPSocket.new(host, port)
        @pending_socket = [token, socket]
      rescue Exception
        @connect_error = [token, $!.class.to_s + ": " + $!.message.to_s]
      ensure
        @connecting = false
      end
    end
  end

  def begin_nonblocking_connect(host, port, token)
    socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP)
    raise "No se pudo activar socket no bloqueante." if !socket.sebi_set_nonblocking(true)
    sockaddr = Socket.sockaddr_in(port, host)
    raise "No se pudo resolver la IP de la sala." if !sockaddr
    ret = Winsock.connect(socket.sebi_fd, sockaddr, sockaddr.size)
    if ret == 0
      @pending_socket = [token, socket]
      @connecting = false
      return
    end
    error = Winsock.WSAGetLastError
    if connect_pending_error?(error)
      @connect_socket = [token, socket]
      timeout = SebiVisualMultiplayer.config_number("connect_timeout_frames", 300)
      timeout = 60 if timeout < 60
      @connect_deadline_frame = Graphics.frame_count + timeout
      @connecting = true
    else
      begin
        socket.close
      rescue Exception
      end
      @connecting = false
      @connect_error = [token, "connect error " + error.to_s]
    end
  rescue Exception
    begin
      socket.close if socket
    rescue Exception
    end
    @connecting = false
    @connect_error = [token, $!.class.to_s + ": " + $!.message.to_s]
  end

  def connect_pending_error?(error)
    return error == 10035 || error == 10036 || error == 10037 || error == 10022
  rescue Exception
    return false
  end

  def finish_async_connect
    if @connect_socket
      token, socket = @connect_socket
      if token != @connect_token || !SebiVisualMultiplayer.enabled?
        begin
          socket.close if socket
        rescue Exception
        end
        @connect_socket = nil
        @connecting = false
      elsif socket && socket.sebi_writable?
        error = socket.sebi_socket_error
        if error == 0
          @pending_socket = [token, socket]
        else
          begin
            socket.close
          rescue Exception
          end
          @connect_error = [token, "connect error " + error.to_s]
        end
        @connect_socket = nil
        @connecting = false
      elsif @connect_deadline_frame && Graphics.frame_count >= @connect_deadline_frame
        begin
          socket.close if socket
        rescue Exception
        end
        @connect_socket = nil
        @connecting = false
        @connect_error = [token, "timeout"]
      end
    end
    if @pending_socket
      token, socket = @pending_socket
      @pending_socket = nil
      if token == @connect_token && SebiVisualMultiplayer.enabled?
        @socket = socket
        @socket.sebi_set_nonblocking(false) if @socket.respond_to?(:sebi_set_nonblocking)
        send_line("HELLO|" + SebiVisualMultiplayer.escape(local_name))
        @buffer = ""
        @connect_error = nil
        SebiVisualMultiplayer.log("connected to " + @connect_host.to_s + ":" + @connect_port.to_s)
      else
        begin
          socket.close if socket
        rescue Exception
        end
      end
    end
    if @connect_error
      token, message = @connect_error
      @connect_error = nil
      if token == @connect_token
        retry_frames = SebiVisualMultiplayer.config_number("retry_frames", 600)
        @next_retry_frame = Graphics.frame_count + retry_frames
        @last_connect_error = message
        SebiVisualMultiplayer.log("connect failed: " + message.to_s)
      end
    end
  rescue Exception
    @socket = nil
  end

  def disconnect
    @connect_token += 1
    begin
      @connect_thread.kill if @connect_thread && @connect_thread.alive?
    rescue Exception
    end
    @connect_thread = nil
    @connecting = false
    if @pending_socket
      begin
        pending = @pending_socket[1]
        pending.close if pending
      rescue Exception
      end
    end
    @pending_socket = nil
    if @connect_socket
      begin
        connecting = @connect_socket[1]
        connecting.close if connecting
      rescue Exception
      end
    end
    @connect_socket = nil
    @connect_error = nil
    begin
      @socket.close if @socket
    rescue Exception
    end
    @socket = nil
    @buffer = ""
    @client_id = nil
    SebiVisualMultiplayer.connection_closed if defined?(SebiVisualMultiplayer)
    retry_frames = SebiVisualMultiplayer.config_number("retry_frames", 600)
    @next_retry_frame = Graphics.frame_count + retry_frames
  end

  def reconnect_now
    disconnect
    @next_retry_frame = 0
  end

  def last_connect_error
    return @last_connect_error
  end

  def clear_connect_error
    @last_connect_error = nil
  end

  def read_available
    guard = 0
    while @socket && @socket.select(0) != 0 && guard < 16
      chunk = @socket.sebi_recv_once(4096)
      break if chunk == ""
      raise Hangup.new("socket closed") if !chunk
      @buffer += chunk
      @buffer = "" if @buffer.length > 8 * 1024 * 1024
      while (idx = @buffer.index("\n"))
        line = @buffer[0...idx]
        @buffer = @buffer[(idx + 1)..-1] || ""
        handle_line(line.sub(/\r$/, ""))
      end
      guard += 1
    end
  end

  def handle_line(line)
    return if !line || line == ""
    parts = line.split(/\|/, -1)
    case parts[0]
    when "WELCOME"
      @client_id = parts[1].to_s
    when "PLAYER"
      return if parts.length < 13
      id = parts[1].to_s
      return if id == @client_id
      SebiVisualMultiplayer.receive_player(
        id,
        SebiVisualMultiplayer.unescape(parts[2]),
        parts[3].to_i,
        parts[4].to_i,
        parts[5].to_i,
        parts[6].to_i,
        parts[7].to_i,
        parts[8].to_i,
        parts[9].to_i,
        SebiVisualMultiplayer.unescape(parts[10]),
        parts[11].to_i,
        parts[12].to_i,
        parts[13, parts.length] || []
      )
    when "LEAVE"
      SebiVisualMultiplayer.remove_player(parts[1].to_s)
    when "MARKER"
      return if parts.length < 6
      SebiVisualMultiplayer.receive_marker(
        parts[1].to_s,
        parts[2].to_i,
        parts[3].to_i,
        parts[4].to_i,
        SebiVisualMultiplayer.unescape(parts[5].to_s)
      )
    when "MARKER_CLEAR"
      SebiVisualMultiplayer.clear_received_marker(parts[1].to_s)
    when "DIRECT"
      from_id = parts[1].to_s
      type = parts[2].to_s
      SebiVisualMultiplayer.receive_direct(from_id, type, parts[3, parts.length] || [])
    when "DIRECT_FAIL"
      SebiVisualMultiplayer.direct_failed(parts[1].to_s)
    end
  end

  def send_line(line)
    return false if !@socket
    data = line.to_s + "\n"
    offset = 0
    while offset < data.length
      sent = @socket.send(data[offset, data.length - offset])
      raise Hangup.new("socket closed while sending") if !sent || sent.to_i <= 0
      offset += sent.to_i
    end
    return true
  end

  def send_direct(remote_id, type, fields)
    return false if !@socket
    values = ["DIRECT", remote_id.to_s, type.to_s]
    for field in fields
      values.push(field.to_s)
    end
    return send_line(values.join("|"))
  rescue Exception
    SebiVisualMultiplayer.log("direct send failed: " + $!.class.to_s + ": " + $!.message.to_s)
    disconnect
    return false
  end

  def send_marker(region, x, y, name)
    return false if !@socket
    values = [
      "MARK",
      region.to_i,
      x.to_i,
      y.to_i,
      SebiVisualMultiplayer.escape(name.to_s)
    ]
    return send_line(values.join("|"))
  rescue Exception
    SebiVisualMultiplayer.log("marker send failed: " + $!.class.to_s + ": " + $!.message.to_s)
    disconnect
    return false
  end

  def clear_marker
    return false if !@socket
    return send_line("CLEAR_MARK")
  rescue Exception
    SebiVisualMultiplayer.log("marker clear failed: " + $!.class.to_s + ": " + $!.message.to_s)
    disconnect
    return false
  end

  def send_position_if_needed
    interval = SebiVisualMultiplayer.config_number("send_interval", 3)
    interval = 1 if interval < 1
    return if Graphics.frame_count - @last_send_frame < interval
    return if !$game_player || !$game_map
    char = $game_player.character_name.to_s
    return if char == ""
    @last_send_frame = Graphics.frame_count
    fields = [
      "POS",
      SebiVisualMultiplayer.escape(local_name),
      $game_map.map_id.to_i,
      $game_player.x.to_i,
      $game_player.y.to_i,
      $game_player.real_x.to_i,
      $game_player.real_y.to_i,
      $game_player.direction.to_i,
      $game_player.pattern.to_i,
      SebiVisualMultiplayer.escape(char),
      $game_player.character_hue.to_i,
      $game_player.opacity.to_i
    ]
    for field in SebiVisualMultiplayer.local_follower_fields
      fields.push(field)
    end
    for field in SebiVisualMultiplayer.local_state_fields
      fields.push(field)
    end
    send_line(fields.join("|"))
  end

  def local_name
    if $Trainer && $Trainer.name && $Trainer.name != ""
      return $Trainer.name.to_s
    end
    return SebiVisualMultiplayer.config_string("name", "Player")
  rescue Exception
    return SebiVisualMultiplayer.config_string("name", "Player")
  end
end

module SebiVisualMultiplayer
  @config = nil
  @players = {}
  @client = nil
  @direct_messages = []
  @sessions = {}
  @pending_session_starts = []
  @session_start_running = false
  @pvp_party_inbox = {}
  @pvp_choice_inbox = {}
  @pvp_switch_inbox = {}
  @pvp_lead_inbox = {}
  @pvp_ready_inbox = {}
  @markers = {}
  @marker_revision = 0
  @follow_player_id = nil
  @follow_transfer_frame = -9999
  @follow_cancel_frame = -9999
  @busy = false
  @last_network_tick_frame = -1
  @last_map_update_frame = -9999
  @network_tick_running = false
  @resume_checked = false
  @auto_join_pending = false
  @startup_message = nil

  def self.multiplayer_dir
    return File.dirname(File.expand_path(__FILE__)) rescue "multiplayer"
  end

  def self.old_legacy_config_path
    return File.join(multiplayer_dir, "multiplayer.ini") rescue "multiplayer/multiplayer.ini"
  end

  def self.legacy_config_path
    return SebiLinkPaths.config_path("multiplayer.ini") if defined?(SebiLinkPaths)
    return old_legacy_config_path
  rescue Exception
    return "SebiLinkConfig/multiplayer.ini"
  end

  def self.raw_file_config_value(key)
    return nil if !defined?(SebiLinkFileConfig)
    return SebiLinkFileConfig.values[key.to_s.downcase]
  rescue Exception
    return nil
  end

  def self.host_blank?(host)
    return host == nil || host.to_s.strip == ""
  end

  def self.normalized_port(port)
    value = port.to_i
    value = 54545 if value <= 0 || value > 65535
    return value
  end

  def self.server_bind_host(host)
    value = host.to_s.strip
    low = value.downcase
    return "0.0.0.0" if value == "" || low == "localhost" || value == "127.0.0.1"
    return value
  end

  def self.local_connect_host_for_create(host)
    value = host.to_s.strip
    low = value.downcase
    return "127.0.0.1" if value == "" || low == "localhost" || value == "0.0.0.0"
    return value
  end

  # Historical callers now persist only the unified INI.
  def self.save_legacy_config
    changes = {}
    (@config || {}).each do |key, value|
      changes[key == "name" ? "player_name" : "multiplayer_" + key] = value
    end
    SebiLinkFileConfig.set_many(changes)
  end

  def self.save_saved_room(mode, host, port)
    return if !defined?(SebiLinkFileConfig)
    port = normalized_port(port)
    SebiLinkFileConfig.set("multiplayer_mode", mode.to_s)
    SebiLinkFileConfig.set("multiplayer_enabled", "true")
    if mode.to_s == "create"
      SebiLinkFileConfig.set("create_host", host.to_s.strip)
      SebiLinkFileConfig.set("create_port", port.to_s)
    elsif mode.to_s == "join"
      SebiLinkFileConfig.set("join_host", host.to_s.strip)
      SebiLinkFileConfig.set("join_port", port.to_s)
    end
  rescue Exception
  end

  def self.clear_saved_room
    if defined?(SebiLinkFileConfig)
      SebiLinkFileConfig.set("multiplayer_mode", "")
      SebiLinkFileConfig.set("multiplayer_enabled", "false")
      SebiLinkFileConfig.set("create_host", "")
      SebiLinkFileConfig.set("create_port", "")
      SebiLinkFileConfig.set("join_host", "")
      SebiLinkFileConfig.set("join_port", "")
    end
    set_config_value("enabled", "false")
    set_config_value("host", "")
    save_legacy_config
  rescue Exception
  end

  def self.load_config
    values = {
      "enabled" => "false",
      "host" => "127.0.0.1",
      "port" => "54545",
      "name" => "Player",
      "send_interval" => "3",
      "remote_smoothing" => "2",
      "connect_timeout_frames" => "300",
      "retry_frames" => "600",
      "fade_after" => "180",
      "hide_after" => "600",
      "pvp_wait_frames" => "108000",
      "debug" => "false"
    }
    values.keys.each do |key|
      target = key == "name" ? "player_name" : "multiplayer_" + key
      stored = SebiLinkFileConfig.values[target]
      values[key] = stored if stored != nil
    end
    missing = {}
    values.each do |key, value|
      target = key == "name" ? "player_name" : "multiplayer_" + key
      missing[target] = value if !SebiLinkFileConfig.has_key?(target)
    end
    SebiLinkFileConfig.set_many(missing) if !missing.empty?
    if defined?(SebiLinkFileConfig)
      mode = raw_file_config_value("multiplayer_mode")
      mode = mode.to_s.strip.downcase if mode != nil
      if mode == "create"
        host = raw_file_config_value("create_host").to_s.strip
        port = raw_file_config_value("create_port")
        if host_blank?(host)
          values["enabled"] = "false"
          values["host"] = ""
        else
          values["enabled"] = "true"
          values["host"] = local_connect_host_for_create(host)
          values["port"] = normalized_port(port).to_s if port != nil && port.to_s != ""
        end
      elsif mode == "join"
        host = raw_file_config_value("join_host").to_s.strip
        port = raw_file_config_value("join_port")
        if host_blank?(host)
          values["enabled"] = "false"
          values["host"] = ""
        else
          values["enabled"] = "true"
          values["host"] = host
          values["port"] = normalized_port(port).to_s if port != nil && port.to_s != ""
        end
      elsif mode != nil
        values["enabled"] = "false"
        values["host"] = ""
      else
        values["enabled"] = SebiLinkFileConfig.get("multiplayer_enabled", values["enabled"])
        values["host"] = SebiLinkFileConfig.get("join_host", values["host"])
        values["port"] = SebiLinkFileConfig.get("join_port", values["port"])
      end
      values["name"] = SebiLinkFileConfig.get("player_name", values["name"])
    end
    @config = values
  rescue Exception
    @config = values
  end

  def self.config
    load_config if !@config
    return @config
  end

  def self.config_string(key, default_value)
    value = config[key]
    return default_value if value == nil || value == ""
    return value.to_s
  end

  def self.config_number(key, default_value)
    value = config[key]
    return default_value if value == nil || value == ""
    return value.to_i
  end

  def self.config_bool(key, default_value)
    value = config[key]
    return default_value if value == nil || value == ""
    value = value.to_s.downcase
    return true if value == "true" || value == "1" || value == "yes" || value == "on" || value == "si"
    return false if value == "false" || value == "0" || value == "no" || value == "off"
    return default_value
  end

  def self.enabled?
    return config_bool("enabled", false)
  end

  def self.set_config_value(key, value)
    key = key.to_s.downcase
    config[key] = value.to_s
    SebiLinkFileConfig.set(key == "name" ? "player_name" : "multiplayer_" + key, value)
  end

  def self.set_enabled(value)
    set_config_value("enabled", value ? "true" : "false")
    SebiLinkFileConfig.set("multiplayer_enabled", value ? "true" : "false") if defined?(SebiLinkFileConfig)
    save_legacy_config
  end

  def self.escape(value)
    value = value.to_s
    value = value.gsub("%", "%25")
    value = value.gsub("|", "%7C")
    value = value.gsub("\n", "%0A")
    value = value.gsub("\r", "%0D")
    return value
  end

  def self.unescape(value)
    value = value.to_s
    value = value.gsub("%0D", "\r")
    value = value.gsub("%0A", "\n")
    value = value.gsub("%7C", "|")
    value = value.gsub("%25", "%")
    return value
  end

  def self.log(message)
    return if !config_bool("debug", false)
    File.open("multiplayer/client.log", "ab") do |file|
      file.write("[" + Time.now.to_s + "] " + message.to_s + "\n")
    end
  rescue Exception
  end

  def self.pvp_log_path
    return SebiLinkPaths.config_path("pvp-handshake.log") if defined?(SebiLinkPaths)
    return "multiplayer/pvp-handshake.log"
  rescue Exception
    return "multiplayer/pvp-handshake.log"
  end

  def self.pvp_log(message, session = nil)
    path = pvp_log_path
    begin
      SebiLinkPaths.ensure_dir(File.dirname(path)) if defined?(SebiLinkPaths)
    rescue Exception
    end
    begin
      File.delete(path) if FileTest.exist?(path) && File.size(path).to_i > 512 * 1024
    rescue Exception
    end
    token = session && session[:token] ? session[:token].to_s : "-"
    role = session && session[:role] ? session[:role].to_s : "-"
    remote = session && session[:remote_name] ? session[:remote_name].to_s : "-"
    frame = Graphics.frame_count rescue 0
    cid = "-"
    begin
      cid = client.client_id.to_s if @client && client.client_id
    rescue Exception
    end
    File.open(path, "ab") do |file|
      file.write("[" + Time.now.to_s + "] frame=" + frame.to_s +
        " cid=" + cid + " token=" + token + " role=" + role +
        " remote=" + remote + " " + message.to_s + "\n")
    end
  rescue Exception
  end

  def self.client
    @client = SebiMultiplayerClient.new if !@client
    return @client
  end

  def self.mark_map_update
    @last_map_update_frame = Graphics.frame_count
  rescue Exception
  end

  def self.global_tick
    return if @network_tick_running
    frame = Graphics.frame_count rescue 0
    return if @last_network_tick_frame == frame
    @last_network_tick_frame = frame
    @network_tick_running = true
    begin
      return if !enabled?
      client.update
      process_direct_messages
      purge_old_players
      SebiBattleSpectator.network_tick if defined?(SebiBattleSpectator)
    ensure
      @network_tick_running = false
    end
  rescue Exception
    @network_tick_running = false
    log("global tick failed: " + $!.class.to_s + ": " + $!.message.to_s)
  end

  def self.update
    resume_saved_room
    show_startup_message_if_ready
    return if !enabled?
    global_tick
    process_pending_session_starts
    check_auto_join_status
    show_startup_message_if_ready
    SebiBattleSpectator.update if defined?(SebiBattleSpectator)
  rescue Exception
    log("update failed: " + $!.class.to_s + ": " + $!.message.to_s)
  end

  def self.in_battle_state?
    return true if $game_temp && ($game_temp.in_battle || $game_temp.battle_calling)
    return true if defined?(PokeBattle_Scene) && $scene && $scene.is_a?(PokeBattle_Scene)
    if defined?(SebiLinkHub) && SebiLinkHub.respond_to?(:in_battle?)
      return true if SebiLinkHub.in_battle?
    end
    return false
  rescue Exception
    return false
  end

  def self.local_busy_state
    return "none" if !$Trainer || !$game_player || !$game_map
    return "battle" if in_battle_state?
    frame = Graphics.frame_count rescue 0
    if $scene && $scene.is_a?(Scene_Map) && @last_map_update_frame &&
       frame - @last_map_update_frame <= 2
      return "map"
    end
    return "menu"
  rescue Exception
    return "menu"
  end

  def self.local_state_fields
    return ["STATE", escape(local_busy_state)]
  rescue Exception
    return ["STATE", "menu"]
  end

  def self.parse_state_fields(fields)
    return "map" if !fields || fields.length == 0
    for i in 0...fields.length
      if fields[i].to_s == "STATE"
        value = (i + 1 < fields.length) ? unescape(fields[i + 1].to_s) : "map"
        return value
      end
    end
    return "map"
  rescue Exception
    return "map"
  end

  def self.local_follower_fields
    fields = []
    followers = []
    begin
      if $PokemonTemp && $PokemonTemp.dependentEvents &&
         $PokemonTemp.dependentEvents.respond_to?("realEvents")
        for event in $PokemonTemp.dependentEvents.realEvents
          next if !event
          next if event.character_name == nil || event.character_name == "" || event.character_name == "nil"
          followers.push(event)
        end
      end
    rescue Exception
    end
    fields.push(followers.length.to_s)
    for event in followers
      fields.push($game_map ? $game_map.map_id.to_i : event.map.map_id.to_i)
      fields.push(event.x.to_i)
      fields.push(event.y.to_i)
      fields.push(event.real_x.to_i)
      fields.push(event.real_y.to_i)
      fields.push(event.direction.to_i)
      fields.push(event.pattern.to_i)
      fields.push(escape(event.character_name.to_s))
      fields.push(event.character_hue.to_i)
      fields.push(event.opacity.to_i)
    end
    return fields
  end

  def self.parse_follower_fields(fields)
    ret = []
    return ret if !fields || fields.length == 0
    count = fields[0].to_i
    index = 1
    for i in 0...count
      break if index + 9 >= fields.length
      ret.push([
        fields[index].to_i,
        fields[index + 1].to_i,
        fields[index + 2].to_i,
        fields[index + 3].to_i,
        fields[index + 4].to_i,
        fields[index + 5].to_i,
        fields[index + 6].to_i,
        unescape(fields[index + 7].to_s),
        fields[index + 8].to_i,
        fields[index + 9].to_i
      ])
      index += 10
    end
    return ret
  end

  def self.receive_player(id, name, map_id, x, y, real_x, real_y, direction, pattern, character_name, hue, opacity, follower_fields = nil)
    return if id == nil || id == ""
    player = @players[id]
    if !player
      player = SebiRemotePlayer.new(id, $game_map)
      @players[id] = player
    end
    player.receive_packet(name, map_id, x, y, real_x, real_y, direction, pattern, character_name, hue, opacity)
    player.receive_state(parse_state_fields(follower_fields))
    player.receive_followers(parse_follower_fields(follower_fields))
  end

  def self.remove_player(id)
    @players.delete(id)
    clear_received_marker(id)
    SebiBattleSpectator.remove_remote(id) if defined?(SebiBattleSpectator)
    if @follow_player_id && @follow_player_id.to_s == id.to_s
      @follow_player_id = nil
      @startup_message = _INTL("El jugador al que seguias se ha desconectado.")
    end
  end

  def self.receive_marker(id, region, x, y, name)
    return if id == nil || id.to_s == ""
    @markers = {} if !@markers
    @markers[id.to_s] = {
      :id => id.to_s,
      :region => region.to_i,
      :x => x.to_i,
      :y => y.to_i,
      :name => name.to_s,
      :expires_at => Time.now.to_f + 60.0
    }
    @marker_revision = (@marker_revision || 0) + 1
  rescue Exception
  end

  def self.clear_received_marker(id)
    return if !@markers
    if @markers.delete(id.to_s)
      @marker_revision = (@marker_revision || 0) + 1
    end
  rescue Exception
  end

  def self.marker_revision
    return @marker_revision || 0
  end

  def self.shared_markers(region = nil)
    @markers = {} if !@markers
    now = Time.now.to_f rescue 0.0
    expired = []
    for id in @markers.keys
      marker = @markers[id]
      next if !marker || !marker[:expires_at]
      expired.push(id) if marker[:expires_at].to_f <= now
    end
    for id in expired
      @markers.delete(id)
    end
    @marker_revision = (@marker_revision || 0) + 1 if expired.length > 0
    ret = []
    for marker in @markers.values
      next if region != nil && marker[:region].to_i != region.to_i
      ret.push(marker)
    end
    return ret
  rescue Exception
    return []
  end

  def self.receive_direct(from_id, type, fields)
    if type.to_s == "BATTLEPARTY"
      pvp_log("recv BATTLEPARTY from=" + from_id.to_s + " fields=" + (fields ? fields.length.to_s : "0") + " bytes=" + (fields && fields[4] ? fields[4].to_s.length.to_s : "0"))
      @pvp_party_inbox[fields[0].to_s] = [from_id.to_s, fields || []]
      return
    end
    if type.to_s == "PVPCHOICES"
      key = fields[0].to_s + ":" + fields[1].to_s
      @pvp_choice_inbox[key] = fields
      return
    end
    if type.to_s == "PVPSWITCH"
      key = fields[0].to_s + ":" + fields[1].to_s
      @pvp_switch_inbox[key] = fields
      return
    end
    if type.to_s == "BATTLELEAD"
      pvp_log("recv BATTLELEAD from=" + from_id.to_s + " value=" + (fields && fields[1] ? fields[1].to_s : ""))
      @pvp_lead_inbox[fields[0].to_s] = fields
      return
    end
    if type.to_s == "BATTLEREADY"
      pvp_log("recv BATTLEREADY from=" + from_id.to_s + " value=" + (fields && fields[1] ? fields[1].to_s : ""))
      @pvp_ready_inbox[fields[0].to_s] = fields
      return
    end
    if (type.to_s == "SPECTATE_WATCH" || type.to_s == "SPECTATE_REQ") && defined?(SebiBattleSpectator)
      SebiBattleSpectator.handle_watch(from_id, fields)
      return
    end
    if type.to_s == "SPECTATE_STATE" && defined?(SebiBattleSpectator)
      SebiBattleSpectator.handle_state(from_id, fields)
      return
    end
    if type.to_s == "SPECTATE_END" && defined?(SebiBattleSpectator)
      SebiBattleSpectator.handle_end(from_id, fields)
      return
    end
    if type.to_s == "SPECTATE_STOP" && defined?(SebiBattleSpectator)
      SebiBattleSpectator.handle_stop(from_id, fields)
      return
    end
    if type.to_s == "SPECTATE_JOIN" && defined?(SebiBattleSpectator)
      SebiBattleSpectator.handle_join(from_id, fields)
      return
    end
    if type.to_s == "SPECTATE_LEAVE" && defined?(SebiBattleSpectator)
      SebiBattleSpectator.handle_leave(from_id, fields)
      return
    end
    if type.to_s == "SPECTATE_FRAME" && defined?(SebiBattleSpectator)
      SebiBattleSpectator.handle_frame(from_id, fields)
      return
    end
    @direct_messages.push([from_id.to_s, type.to_s, fields || []])
  end

  def self.direct_failed(id)
    log("direct message failed for " + id.to_s)
    SebiBattleSpectator.remove_remote(id) if defined?(SebiBattleSpectator)
  end

  def self.local_name
    if $Trainer && $Trainer.name && $Trainer.name != ""
      return $Trainer.name.to_s
    end
    return config_string("name", "Player")
  rescue Exception
    return config_string("name", "Player")
  end

  def self.make_token
    base = client.client_id ? client.client_id.to_s : "local"
    return base + "-" + Graphics.frame_count.to_s + "-" + rand(1000000).to_s
  end

  def self.safe_to_open_ui?
    return false if @busy
    return false if !$Trainer || !$game_player || !$game_map
    return false if local_busy_state != "map"
    return false if $game_temp && $game_temp.in_battle
    return false if $game_temp && $game_temp.battle_calling
    return false if $game_temp && $game_temp.message_window_showing
    begin
      return false if pbMapInterpreterRunning?
    rescue Exception
    end
    return true
  end

  def self.blocking_request_reason
    state = local_busy_state
    return _INTL("esta en combate") if state == "battle"
    return _INTL("esta en un menu") if state == "menu"
    return _INTL("esta en combate") if $game_temp && $game_temp.in_battle
    return _INTL("esta entrando en combate") if $game_temp && $game_temp.battle_calling
    return _INTL("esta ocupado en otra accion multijugador") if @busy
    return _INTL("ya tiene una solicitud o sesion pendiente") if @sessions && @sessions.length > 0
    return _INTL("no esta dentro de una partida cargada") if !$Trainer || !$game_player || !$game_map
    return _INTL("tiene otro mensaje abierto") if $game_temp && $game_temp.message_window_showing
    begin
      return _INTL("esta ocupado en un evento") if pbMapInterpreterRunning?
    rescue Exception
    end
    return nil
  end

  def self.send_request_denied(from_id, fields, reason)
    return if !fields || fields.length < 4
    token = fields[0].to_s
    action = fields[1].to_s
    mode = fields[2].to_s
    client.send_direct(from_id, "RES", [
      token,
      "busy",
      action,
      mode,
      escape(local_name),
      escape(reason.to_s)
    ])
  rescue Exception
  end

  def self.action_label(action, mode = nil)
    return "intercambio" if action == "trade"
    return "combate doble" if action == "battle" && mode == "double"
    return "combate individual" if action == "battle"
    return action.to_s
  end

  def self.online_players(include_different_map = true)
    purge_old_players
    list = []
    for player in @players.values
      next if !include_different_map && $game_map && player.remote_map_id != $game_map.map_id
      next if player.last_seen && Graphics.frame_count - player.last_seen > config_number("hide_after", 600)
      list.push(player)
    end
    return list
  end

  def self.remote_at(x, y, map_id = nil)
    map_id = $game_map.map_id if map_id == nil && $game_map
    for player in players_for_map(map_id)
      next if player.transparent
      return player if player.x == x && player.y == y
    end
    return nil
  end

  def self.remote_in_front
    return nil if !$game_player || !$game_map
    x = $game_player.x + ($game_player.direction == 6 ? 1 : $game_player.direction == 4 ? -1 : 0)
    y = $game_player.y + ($game_player.direction == 2 ? 1 : $game_player.direction == 8 ? -1 : 0)
    return remote_at(x, y, $game_map.map_id)
  end

  def self.mouse_position
    if defined?(Game_Mouse) && $mouse
      begin
        return [$mouse.x.to_i, $mouse.y.to_i] if $mouse.respond_to?(:x) && $mouse.respond_to?(:y) && $mouse.x.to_i >= 0 && $mouse.y.to_i >= 0
      rescue Exception
      end
    end
    return Mouse.getMousePos if defined?(Mouse) && Mouse.respond_to?(:getMousePos)
    return nil
  rescue Exception
    return nil
  end

  def self.left_mouse_triggered?
    triggered = false
    pressed = false
    begin
      triggered = true if defined?(Game_Mouse) && $mouse && $mouse.respond_to?(:click?) && $mouse.click?
    rescue Exception
    end
    begin
      triggered = true if !triggered && defined?(Input::LeftMouseKey) && Input.respond_to?(:triggerex?) && Input.triggerex?(Input::LeftMouseKey)
    rescue Exception
    end
    begin
      triggered = true if !triggered && Input.respond_to?(:triggerex?) && Input.triggerex?(0x01)
    rescue Exception
    end
    begin
      pressed = true if defined?(Input::LeftMouseKey) && Input.respond_to?(:repeatcount) && Input.repeatcount(Input::LeftMouseKey).to_i > 0
    rescue Exception
    end
    begin
      pressed = true if !pressed && Input.respond_to?(:repeatcount) && Input.repeatcount(0x01).to_i > 0
    rescue Exception
    end
    was_pressed = @left_mouse_was_pressed ? true : false
    @left_mouse_was_pressed = pressed
    return true if triggered
    return pressed && !was_pressed
  rescue Exception
    return false
  end

  def self.mouse_tile_position
    return nil if !$game_map
    pos = mouse_position
    return nil if !pos || pos.length < 2
    mx = pos[0].to_i
    my = pos[1].to_i
    x = ((mx * 4 + $game_map.display_x.to_i) / Game_Map.realResX).floor
    y = ((my * 4 + $game_map.display_y.to_i) / Game_Map.realResY).floor
    return [x, y]
  rescue Exception
    return nil
  end

  def self.remote_near_tile(tile_x, tile_y, map_id = nil, radius = 2)
    map_id = $game_map.map_id if map_id == nil && $game_map
    best = nil
    best_score = nil
    for player in players_for_map(map_id)
      next if player.transparent
      dx = (player.x.to_i - tile_x.to_i).abs
      dy = (player.y.to_i - tile_y.to_i).abs
      next if dx > radius.to_i || dy > radius.to_i
      score = dx + dy
      if best_score == nil || score < best_score
        best = player
        best_score = score
      end
    end
    return best
  rescue Exception
    return nil
  end

  def self.remote_under_mouse
    return nil if !$game_map
    pos = mouse_position
    return nil if !pos || pos.length < 2
    mx = pos[0].to_i
    my = pos[1].to_i
    best = nil
    best_dist = nil
    for player in players_for_map($game_map.map_id)
      next if player.transparent
      sx = player.screen_x rescue nil
      sy = player.screen_y rescue nil
      next if sx == nil || sy == nil
      # Sprite_Character uses screen_x/screen_y near the bottom center of the sprite.
      next if mx < sx - 32 || mx > sx + 32 || my < sy - 72 || my > sy + 16
      dist = (mx - sx) * (mx - sx) + (my - sy) * (my - sy)
      if best_dist == nil || dist < best_dist
        best = player
        best_dist = dist
      end
    end
    return best if best
    tile = mouse_tile_position
    return nil if !tile
    return remote_near_tile(tile[0], tile[1], $game_map.map_id, 2)
  rescue Exception
    return nil
  end

  def self.open_player_quick_menu(player)
    return if !player
    commands = [_INTL("Seguir"), _INTL("TP a este jugador"), _INTL("Cancelar")]
    cmd = Kernel.pbMessage(_INTL("Que quieres hacer con {1}?", player.remote_name), commands, commands.length)
    case cmd
    when 0
      follow_player(player)
      return :follow
    when 1
      teleport_to_player(player)
      return :teleport
    end
    return :cancel
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir el menu del jugador."))
    return :error
  end

  def self.update_map_player_click
    return if !enabled? || @busy
    return if !$game_temp || !$game_player || !$game_map
    return if local_busy_state != "map"
    return if $game_temp.message_window_showing || $game_temp.player_transferring
    begin
      return if pbMapInterpreterRunning?
    rescue Exception
    end
    frame = Graphics.frame_count rescue 0
    return if frame - (@last_remote_mouse_click_frame || -9999) < 15
    return if !left_mouse_triggered?
    player = remote_under_mouse
    return if !player
    @last_remote_mouse_click_frame = frame
    open_player_quick_menu(player)
  rescue Exception
  end

  def self.room_hosted?
    return @hosted_room ? true : false
  end

  def self.room_status
    if room_hosted?
      host = @hosted_room_host || config_string("host", "127.0.0.1")
      port = @hosted_room_port || config_number("port", 54545)
      return _INTL("Sala creada: {1}:{2}", host, port)
    elsif enabled?
      status = client.connected? ? _INTL("conectado") : _INTL("conectando")
      return _INTL("Unido: {1}:{2} ({3})", config_string("host", "127.0.0.1"), config_number("port", 54545), status)
    end
    return _INTL("sin sala")
  rescue Exception
    return _INTL("sin sala")
  end

  def self.ask_text(message, default_value, max_length = 64)
    begin
      SebiControls.free_text_cancel_nil = true if defined?(SebiControls) && SebiControls.respond_to?(:free_text_cancel_nil=)
      value = Kernel.pbMessageFreeText(message, default_value.to_s, false, max_length)
    ensure
      SebiControls.free_text_cancel_nil = false if defined?(SebiControls) && SebiControls.respond_to?(:free_text_cancel_nil=)
    end
    return nil if value == nil
    value = default_value if value.to_s.strip == ""
    return value.to_s.strip
  rescue Exception
    return default_value.to_s
  end

  def self.ask_port(message, default_value)
    params = ChooseNumberParams.new
    params.setRange(1, 65535)
    params.setDefaultValue(default_value.to_i)
    params.setCancelValue(-1)
    value = Kernel.pbMessageChooseNumber(message, params).to_i
    return nil if value < 0
    return value
  rescue Exception
    return default_value.to_i
  end

  def self.shell_quote(value)
    return "\"" + value.to_s.gsub("\"", "\\\"") + "\""
  end

  def self.background_server_script
    return File.join(multiplayer_dir, "start-server-background.ps1") rescue "multiplayer/start-server-background.ps1"
  end

  def self.stop_server_script
    return File.join(multiplayer_dir, "stop-server.ps1") rescue "multiplayer/stop-server.ps1"
  end

  def self.server_pid_path
    if defined?(SebiLinkPaths)
      path = SebiLinkPaths.config_path("server/server.pid")
      SebiLinkPaths.migrate_file(File.join(multiplayer_dir, "server.pid"), path)
      return path
    end
    return File.join(multiplayer_dir, "server.pid") rescue "multiplayer/server.pid"
  end

  def self.start_hosted_server(host, port)
    script = background_server_script
    if !FileTest.exist?(script)
      Kernel.pbMessage(_INTL("No se encontro el script para arrancar el servidor."))
      return false
    end
    bind_host = server_bind_host(host)
    params = "-ExecutionPolicy Bypass -WindowStyle Hidden -File " + shell_quote(script) +
             " -Port " + normalized_port(port).to_s + " -BindHost " + shell_quote(bind_host)
    if defined?(Win32API)
      shell = Win32API.new("shell32", "ShellExecuteA", "LPPPPI", "I")
      shell.call(0, "open", "powershell.exe", params, nil, 0)
    else
      system("powershell.exe " + params)
    end
    @hosted_room = true
    @hosted_room_host = host
    @hosted_room_bind_host = bind_host
    @hosted_room_port = normalized_port(port)
    return true
  rescue Exception
    log("server start failed: " + $!.class.to_s + ": " + $!.message.to_s)
    Kernel.pbMessage(_INTL("No se pudo arrancar el servidor en segundo plano."))
    return false
  end

  def self.stop_hosted_server(show_message = true)
    return if !@hosted_room && !FileTest.exist?(server_pid_path)
    script = stop_server_script
    if FileTest.exist?(script)
      params = "-ExecutionPolicy Bypass -WindowStyle Hidden -File " + shell_quote(script)
      if defined?(Win32API)
        shell = Win32API.new("shell32", "ShellExecuteA", "LPPPPI", "I")
        shell.call(0, "open", "powershell.exe", params, nil, 0)
      else
        system("powershell.exe " + params)
      end
    end
    @hosted_room = false
    @hosted_room_host = nil
    @hosted_room_bind_host = nil
    @hosted_room_port = nil
    Kernel.pbMessage(_INTL("Sala cerrada.")) if show_message
  rescue Exception
    @hosted_room = false
    @hosted_room_host = nil
    @hosted_room_bind_host = nil
    @hosted_room_port = nil
  end

  def self.apply_connection(host, port, mode_key = nil)
    host = host.to_s.strip
    host = "127.0.0.1" if host == ""
    port = normalized_port(port)
    set_enabled(true)
    set_config_value("host", host)
    set_config_value("port", port.to_s)
    save_legacy_config
    connection_closed
    client.reconnect_now if @client
    ensure_remote_layer
  end

  def self.connection_closed
    if @players
      for id in @players.keys
        SebiBattleSpectator.remove_remote(id) if defined?(SebiBattleSpectator)
      end
      @players.clear
    end
    if @markers && @markers.length > 0
      @markers.clear
      @marker_revision = (@marker_revision || 0) + 1
    end
    @sessions.clear if @sessions
    @direct_messages.clear if @direct_messages
    @pending_session_starts.clear if @pending_session_starts
    @pvp_party_inbox.clear if @pvp_party_inbox
    @pvp_choice_inbox.clear if @pvp_choice_inbox
    @pvp_switch_inbox.clear if @pvp_switch_inbox
    @pvp_lead_inbox.clear if @pvp_lead_inbox
    @pvp_ready_inbox.clear if @pvp_ready_inbox
    stop_following(false)
  rescue Exception
  end

  def self.ensure_remote_layer
    return if !enabled?
    return if !$scene || !$scene.is_a?(Scene_Map) || !$scene.respond_to?(:spriteset)
    spriteset = $scene.spriteset
    return if !spriteset
    users = spriteset.instance_variable_get("@usersprites") rescue nil
    if users
      for sprite in users
        return if sprite && sprite.is_a?(SebiRemotePlayerLayer) && !sprite.disposed?
      end
    end
    viewport = spriteset.instance_variable_get("@viewport1") rescue nil
    return if !viewport
    spriteset.addUserSprite(SebiRemotePlayerLayer.new(viewport, spriteset.map))
  rescue Exception
    log("ensure remote layer failed: " + $!.class.to_s + ": " + $!.message.to_s)
  end

  def self.create_room
    default_host = SebiLinkFileConfig.get("create_host", config_string("host", "127.0.0.1")) rescue "127.0.0.1"
    default_port = SebiLinkFileConfig.get_int("create_port", config_number("port", 54545)) rescue 54545
    host = ask_text(_INTL("IP de la sala. Puedes dejar 127.0.0.1; el servidor escuchara tambien para Tailscale."), default_host, 64)
    return if host == nil
    port = ask_port(_INTL("Puerto de la sala."), default_port)
    return if port == nil
    return if !start_hosted_server(host, port)
    connect_host = local_connect_host_for_create(host)
    apply_connection(connect_host, port)
    save_saved_room("create", host, port)
    Kernel.pbMessage(_INTL("Sala creada en {1}:{2}. Tus amigos se unen con tu IP de Tailscale y ese puerto.", host, port))
  end

  def self.join_room
    default_host = SebiLinkFileConfig.get("join_host", config_string("host", "127.0.0.1")) rescue "127.0.0.1"
    default_port = SebiLinkFileConfig.get_int("join_port", config_number("port", 54545)) rescue 54545
    host = ask_text(_INTL("IP de la sala a la que te quieres unir."), default_host, 64)
    return if host == nil
    port = ask_port(_INTL("Puerto de la sala."), default_port)
    return if port == nil
    @hosted_room = false
    apply_connection(host, port)
    save_saved_room("join", host, port)
    @auto_join_pending = false
    Kernel.pbMessage(_INTL("Conectando a {1}:{2}.", host, port))
  end

  def self.apply_player_name(name)
    name = name.to_s.strip
    return if name == ""
    set_config_value("name", name)
    SebiLinkFileConfig.set("player_name", name) if defined?(SebiLinkFileConfig)
    save_legacy_config
  rescue Exception
  end

  def self.create_room_direct(host, port, name = nil)
    default_host = SebiLinkFileConfig.get("create_host", config_string("host", "127.0.0.1")) rescue "127.0.0.1"
    host = host.to_s.strip
    host = default_host if host == ""
    port = normalized_port(port)
    apply_player_name(name)
    return if !start_hosted_server(host, port)
    connect_host = local_connect_host_for_create(host)
    apply_connection(connect_host, port)
    save_saved_room("create", host, port)
    Kernel.pbMessage(_INTL("Sala creada en {1}:{2}.", host, port))
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo crear la sala."))
  end

  def self.join_room_direct(host, port, name = nil)
    default_host = SebiLinkFileConfig.get("join_host", config_string("host", "127.0.0.1")) rescue "127.0.0.1"
    host = host.to_s.strip
    host = default_host if host == ""
    port = normalized_port(port)
    apply_player_name(name)
    @hosted_room = false
    apply_connection(host, port)
    save_saved_room("join", host, port)
    @auto_join_pending = false
    Kernel.pbMessage(_INTL("Conectando a {1}:{2}.", host, port))
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo unir a la sala."))
  end

  def self.leave_room
    stop_hosted_server(false) if room_hosted?
    clear_shared_marker(false) if @client && @client.connected?
    stop_following(false)
    SebiBattleSpectator.stop_watching(false) if defined?(SebiBattleSpectator)
    client.disconnect if @client
    @players.clear if @players
    @markers.clear if @markers
    @marker_revision = (@marker_revision || 0) + 1
    @sessions.clear if @sessions
    @direct_messages.clear if @direct_messages
    @pending_session_starts.clear if @pending_session_starts
    @pvp_party_inbox.clear if @pvp_party_inbox
    @pvp_choice_inbox.clear if @pvp_choice_inbox
    @pvp_switch_inbox.clear if @pvp_switch_inbox
    @pvp_lead_inbox.clear if @pvp_lead_inbox
    @pvp_ready_inbox.clear if @pvp_ready_inbox
    @auto_join_pending = false
    @resume_checked = true
    clear_saved_room
    Kernel.pbMessage(_INTL("Has salido de la sala multijugador."))
  end

  def self.resume_saved_room
    return if @resume_checked
    @resume_checked = true
    return if !defined?(SebiLinkFileConfig)
    mode = raw_file_config_value("multiplayer_mode")
    return if mode == nil
    mode = mode.to_s.strip.downcase
    if mode == "create"
      host = raw_file_config_value("create_host").to_s.strip
      return if host_blank?(host)
      port = normalized_port(raw_file_config_value("create_port"))
      if start_hosted_server(host, port)
        apply_connection(local_connect_host_for_create(host), port)
      else
        @startup_message = _INTL("No se pudo recrear la sala multijugador guardada.")
        set_enabled(false)
      end
    elsif mode == "join"
      host = raw_file_config_value("join_host").to_s.strip
      return if host_blank?(host)
      port = normalized_port(raw_file_config_value("join_port"))
      @hosted_room = false
      apply_connection(host, port)
      @auto_join_pending = true
      @auto_join_host = host
      @auto_join_port = port
      @auto_join_deadline = Graphics.frame_count + config_number("auto_join_timeout_frames", 600)
      client.clear_connect_error if @client
    else
      set_enabled(false)
    end
  rescue Exception
    @startup_message = _INTL("No se pudo cargar la sala multijugador guardada.")
    set_enabled(false)
  end

  def self.check_auto_join_status
    return if !@auto_join_pending
    if client.connected?
      @auto_join_pending = false
      return
    end
    message = nil
    if client.last_connect_error
      message = _INTL("No se pudo unir a la sala {1}:{2}.", @auto_join_host, @auto_join_port)
      client.clear_connect_error
    elsif @auto_join_deadline && Graphics.frame_count >= @auto_join_deadline
      message = _INTL("No se pudo unir a la sala {1}:{2}.", @auto_join_host, @auto_join_port)
    end
    if message
      @auto_join_pending = false
      @startup_message = message
      client.disconnect if @client
      set_enabled(false)
    end
  rescue Exception
    @auto_join_pending = false
  end

  def self.show_startup_message_if_ready
    return if @startup_message == nil || @startup_message == ""
    return if !safe_to_open_ui?
    message = @startup_message
    @startup_message = nil
    Kernel.pbMessage(message)
  rescue Exception
  end

  def self.quick_room_host
    return SebiLinkFileConfig.get("join_host", SebiLinkFileConfig.get("create_host", config_string("host", "127.0.0.1"))) if defined?(SebiLinkFileConfig)
    return config_string("host", "127.0.0.1")
  rescue Exception
    return "127.0.0.1"
  end

  def self.quick_room_port
    return SebiLinkFileConfig.get_int("join_port", SebiLinkFileConfig.get_int("create_port", config_number("port", 54545))) if defined?(SebiLinkFileConfig)
    return config_number("port", 54545)
  rescue Exception
    return 54545
  end

  def self.edit_multiplayer_quick_settings
    host = ask_text(_INTL("IP/Tailscale para crear o unirse rapido."), quick_room_host, 64)
    return if host == nil
    port = ask_port(_INTL("Puerto para crear o unirse rapido."), quick_room_port)
    return if port == nil
    name = ask_text(_INTL("Nombre visible en la sala."), config_string("name", local_name), 32)
    return if name == nil
    if defined?(SebiLinkFileConfig)
      SebiLinkFileConfig.set("create_host", host)
      SebiLinkFileConfig.set("create_port", normalized_port(port).to_s)
      SebiLinkFileConfig.set("join_host", host)
      SebiLinkFileConfig.set("join_port", normalized_port(port).to_s)
    end
    apply_player_name(name)
    Kernel.pbMessage(_INTL("Datos multijugador actualizados."))
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudieron actualizar los datos."))
  end

  def self.create_room_quick
    create_room_direct(quick_room_host, quick_room_port, config_string("name", local_name))
  end

  def self.join_room_quick
    join_room_direct(quick_room_host, quick_room_port, config_string("name", local_name))
  end

  def self.visual_multiplayer_actions
    return [
      { :title => _INTL("Crear sala"), :desc => _INTL("Anfitrion rapido con los datos guardados."), :action => :create },
      { :title => _INTL("Unirse"), :desc => _INTL("Conecta rapido a la IP y puerto del panel."), :action => :join },
      { :title => _INTL("Editar datos"), :desc => _INTL("Cambia IP, puerto y nombre de jugador."), :action => :edit },
      { :title => _INTL("Jugadores"), :desc => _INTL("Elige un amigo para TP, seguir, trade o combate."), :action => :players },
      { :title => _INTL("Combatir"), :desc => _INTL("Reta a un jugador con reglas PvP personalizadas."), :action => :battle },
      { :title => _INTL("Espectar"), :desc => _INTL("Mira el combate de un jugador conectado."), :action => :spectate },
      { :title => _INTL("Borrar marcador"), :desc => _INTL("Quita tu punto compartido del mapa regional."), :action => :marker },
      { :title => _INTL("Salir de sala"), :desc => _INTL("Abandona o cierra la sala actual."), :action => :leave },
      { :title => _INTL("Cerrar menu"), :desc => _INTL("Vuelve al juego."), :action => :close }
    ]
  end

  def self.visual_menu_bg
    @visual_menu_bg = AnimatedBitmap.new("Graphics/Pictures/partybg") if !@visual_menu_bg
    return @visual_menu_bg.bitmap
  rescue Exception
    return nil
  end

  def self.visual_font(bitmap, size = 16)
    pbSetSystemFont(bitmap) if defined?(pbSetSystemFont)
    if bitmap.respond_to?(:font) && bitmap.font
      bitmap.font.name = "Power Green Small" if bitmap.font.respond_to?(:name=)
      bitmap.font.size = size.to_i if bitmap.font.respond_to?(:size=)
      bitmap.font.bold = false if bitmap.font.respond_to?(:bold=)
    end
  rescue Exception
  end

  def self.visual_text(bitmap, text, x, y, align = 0, base = nil, shadow = nil, size = 16)
    return if !bitmap
    visual_font(bitmap, size)
    base = Color.new(248, 248, 248) if !base
    shadow = Color.new(24, 32, 48) if !shadow
    pbDrawTextPositions(bitmap, [[text.to_s, x, y, align, base, shadow]])
  rescue Exception
  end

  def self.visual_fit_text(bitmap, text, max_width)
    value = text.to_s
    visual_font(bitmap, 15)
    return value if (bitmap.text_size(value).width rescue 0) <= max_width.to_i
    suffix = "..."
    while value.length > 1 && (bitmap.text_size(value + suffix).width rescue 9999) > max_width.to_i
      value = value[0, value.length - 1]
    end
    return value + suffix
  rescue Exception
    return text.to_s
  end

  def self.visual_box(bitmap, x, y, w, h, fill, edge = nil)
    edge = Color.new(22, 46, 84) if !edge
    bitmap.fill_rect(x, y, w, h, edge)
    bitmap.fill_rect(x + 2, y + 2, w - 4, h - 4, fill)
  rescue Exception
  end

  def self.draw_visual_multiplayer_menu(bitmap, selected)
    return if !bitmap
    bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(28, 56, 96))
    bg = visual_menu_bg
    if bg
      bitmap.stretch_blt(Rect.new(0, 0, Graphics.width, Graphics.height), bg, Rect.new(0, 0, bg.width, bg.height))
    else
      bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(28, 56, 96))
      for x in 0..Graphics.width
        bitmap.fill_rect(x, 0, 1, Graphics.height, Color.new(42, 78, 132)) if x % 16 == 0
      end
      for y in 0..Graphics.height
        bitmap.fill_rect(0, y, Graphics.width, 1, Color.new(42, 78, 132)) if y % 16 == 0
      end
    end
    bitmap.fill_rect(0, 0, Graphics.width, 42, Color.new(22, 42, 76))
    visual_text(bitmap, _INTL("SebiLink - Multijugador"), Graphics.width / 2, 9, 2, Color.new(248, 248, 248), Color.new(0, 0, 0), 20)

    actions = visual_multiplayer_actions
    left_x = 10
    left_y = 54
    row_h = 32
    visual_box(bitmap, left_x, left_y - 8, 226, 302, Color.new(42, 74, 118, 210), Color.new(20, 36, 64))
    for i in 0...actions.length
      y = left_y + i * row_h
      selected_row = i == selected.to_i
      fill = selected_row ? Color.new(248, 224, 72) : Color.new(40, 156, 82)
      edge = selected_row ? Color.new(255, 248, 152) : Color.new(20, 92, 48)
      bitmap.fill_rect(left_x + 8, y, 210, 28, edge)
      bitmap.fill_rect(left_x + 11, y + 3, 204, 22, fill)
      base = selected_row ? Color.new(36, 36, 40) : Color.new(248, 248, 248)
      shadow = selected_row ? Color.new(255, 255, 255, 0) : Color.new(16, 48, 28)
      visual_text(bitmap, actions[i][:title], left_x + 18, y + 2, 0, base, shadow, 16)
    end

    right_x = 248
    visual_box(bitmap, right_x, 54, Graphics.width - right_x - 10, 112, Color.new(238, 244, 248), Color.new(28, 56, 92))
    status_color = (enabled? && client.connected?) ? Color.new(36, 156, 76) : (enabled? ? Color.new(226, 174, 42) : Color.new(132, 140, 148))
    bitmap.fill_rect(right_x + 10, 66, 74, 20, status_color)
    visual_text(bitmap, (enabled? && client.connected?) ? _INTL("EN SALA") : (enabled? ? _INTL("CONECTANDO") : _INTL("SIN SALA")), right_x + 47, 66, 2, Color.new(248, 248, 248), Color.new(0, 0, 0), 14)
    visual_text(bitmap, room_status, right_x + 12, 91, 0, Color.new(40, 44, 52), Color.new(255, 255, 255, 0), 15)
    visual_text(bitmap, _INTL("Nombre: {1}", config_string("name", local_name)), right_x + 12, 114, 0, Color.new(40, 44, 52), Color.new(255, 255, 255, 0), 15)
    visual_text(bitmap, _INTL("Rapido: {1}:{2}", quick_room_host, quick_room_port), right_x + 12, 137, 0, Color.new(40, 44, 52), Color.new(255, 255, 255, 0), 15)

    visual_box(bitmap, right_x, 176, Graphics.width - right_x - 10, 146, Color.new(238, 244, 248), Color.new(28, 56, 92))
    players = online_players(true)
    visual_text(bitmap, _INTL("Jugadores en sala ({1})", players.length), right_x + 12, 184, 0, Color.new(40, 44, 52), Color.new(255, 255, 255, 0), 16)
    if players.length == 0
      visual_text(bitmap, enabled? ? _INTL("Esperando amigos...") : _INTL("Crea o unete a una sala."), right_x + 22, 220, 0, Color.new(80, 86, 96), Color.new(255, 255, 255, 0), 15)
    else
      max_rows = 5
      for i in 0...[players.length, max_rows].min
        player = players[i]
        y = 212 + i * 21
        state = player.respond_to?(:busy_state) ? player.busy_state.to_s : "map"
        state_text = state == "battle" ? _INTL("combate") : (state == "menu" ? _INTL("menu") : (state == "busy" ? _INTL("ocupado") : _INTL("mapa")))
        same_map = $game_map && player.remote_map_id.to_i == $game_map.map_id.to_i
        map_text = same_map ? _INTL("aqui") : _INTL("mapa {1}", player.remote_map_id.to_i)
        visual_text(bitmap, visual_fit_text(bitmap, player.remote_name.to_s, 108), right_x + 16, y, 0, Color.new(40, 44, 52), Color.new(255, 255, 255, 0), 15)
        visual_text(bitmap, _INTL("{1} - {2}", state_text, map_text), right_x + 126, y, 0, Color.new(76, 82, 94), Color.new(255, 255, 255, 0), 13)
      end
      if players.length > max_rows
        visual_text(bitmap, _INTL("+{1} mas", players.length - max_rows), right_x + 16, 212 + max_rows * 21, 0, Color.new(76, 82, 94), Color.new(255, 255, 255, 0), 13)
      end
    end

    visual_box(bitmap, 10, Graphics.height - 42, Graphics.width - 20, 34, Color.new(66, 82, 104, 225), Color.new(32, 48, 72))
    desc = actions[selected.to_i] ? actions[selected.to_i][:desc] : ""
    visual_text(bitmap, visual_fit_text(bitmap, desc, Graphics.width - 210), 24, Graphics.height - 36, 0, Color.new(248, 248, 248), Color.new(24, 32, 48), 14)
    visual_text(bitmap, _INTL("A: ejecutar   B: salir"), Graphics.width - 22, Graphics.height - 36, 1, Color.new(248, 248, 248), Color.new(24, 32, 48), 14)
  rescue Exception
    begin
      bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(28, 56, 96))
      bitmap.fill_rect(10, 10, Graphics.width - 20, 64, Color.new(238, 244, 248))
      visual_text(bitmap, _INTL("No se pudo dibujar el menu multijugador."), 22, 20, 0, Color.new(40, 44, 52), Color.new(255, 255, 255, 0), 16)
      visual_text(bitmap, _INTL("Pulsa B para volver."), 22, 44, 0, Color.new(40, 44, 52), Color.new(255, 255, 255, 0), 16)
    rescue Exception
    end
  end

  def self.visual_accept_trigger?
    return true if defined?(SebiControls) && SebiControls.button_a_trigger?
    return Input.trigger?(Input::C)
  rescue Exception
    return false
  end

  def self.visual_cancel_trigger?
    return true if defined?(SebiControls) && SebiControls.button_b_trigger?
    return Input.trigger?(Input::B)
  rescue Exception
    return false
  end

  def self.execute_visual_multiplayer_action(action)
    case action
    when :create
      create_room_quick
    when :join
      join_room_quick
    when :edit
      edit_multiplayer_quick_settings
    when :players
      open_players_menu
    when :battle
      open_battle_menu
    when :spectate
      open_spectator_menu
    when :marker
      clear_shared_marker
    when :leave
      leave_room
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo ejecutar la accion multijugador."))
  end

  def self.open_visual_main_menu
    viewport = nil
    overlay = nil
    old_busy = @busy
    @busy = true
    viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    # SebiLink is opened from the pause menu inside pbFadeOutIn(99999).
    # This viewport must sit above that fade layer or the menu appears black.
    viewport.z = 100100
    overlay = BitmapSprite.new(Graphics.width, Graphics.height, viewport)
    overlay.z = 1
    selected = 0
    actions = visual_multiplayer_actions
    draw_visual_multiplayer_menu(overlay.bitmap, selected)
    loop do
      Graphics.update
      Input.update
      global_tick
      old_selected = selected
      if Input.trigger?(Input::UP)
        selected = (selected - 1) % actions.length
      elsif Input.trigger?(Input::DOWN)
        selected = (selected + 1) % actions.length
      elsif visual_cancel_trigger?
        break
      elsif visual_accept_trigger?
        action = actions[selected][:action]
        break if action == :close
        begin
          overlay.bitmap.dispose if overlay && overlay.bitmap && !overlay.bitmap.disposed?
          overlay.dispose if overlay && !overlay.disposed?
          viewport.dispose if viewport && !viewport.disposed?
          overlay = nil
          viewport = nil
        rescue Exception
        end
        @busy = old_busy
        execute_visual_multiplayer_action(action)
        break
      end
      if old_selected != selected || (Graphics.frame_count % 30 == 0)
        draw_visual_multiplayer_menu(overlay.bitmap, selected)
      end
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir el menu multijugador."))
  ensure
    @busy = old_busy
    begin
      overlay.bitmap.dispose if overlay && overlay.bitmap && !overlay.bitmap.disposed?
      overlay.dispose if overlay && !overlay.disposed?
      viewport.dispose if viewport && !viewport.disposed?
    rescue Exception
    end
  end

  def self.open_main_menu
    open_visual_main_menu
  end

  def self.open_players_menu
    if !enabled? || !client.connected?
      Kernel.pbMessage(_INTL("No hay conexion con el servidor multijugador."))
      return
    end
    players = online_players(true)
    if players.length == 0
      Kernel.pbMessage(_INTL("No hay jugadores conectados todavia."))
      return
    end
    commands = []
    for player in players
      suffix = ($game_map && player.remote_map_id == $game_map.map_id) ? "" : _INTL(" (otro mapa)")
      if player.respond_to?(:busy_state)
        suffix += _INTL(" (combate)") if player.busy_state == "battle"
        suffix += _INTL(" (menu)") if player.busy_state == "menu"
        suffix += _INTL(" (ocupado)") if player.busy_state == "busy"
      end
      commands.push(player.remote_name.to_s + suffix)
    end
    commands.push(_INTL("Cancelar"))
    cmd = Kernel.pbMessage(_INTL("Elige un jugador."), commands, commands.length)
    return if cmd < 0 || cmd >= players.length
    open_player_menu(players[cmd])
  end

  def self.request_close_sebilink_menu
    return if !@sebilink_menu_open
    @close_sebilink_menu_after_action = true
    @close_pause_menu_after_action = true if $game_temp && $game_temp.in_menu
  rescue Exception
  end

  def self.sebilink_menu_open=(value)
    @sebilink_menu_open = value ? true : false
  rescue Exception
  end

  def self.consume_close_sebilink_menu?
    value = @close_sebilink_menu_after_action ? true : false
    @close_sebilink_menu_after_action = false
    return value
  rescue Exception
    return false
  end

  def self.consume_close_pause_menu?
    value = @close_pause_menu_after_action ? true : false
    @close_pause_menu_after_action = false
    return value
  rescue Exception
    return false
  end

  def self.open_teleport_menu
    if !enabled? || !client.connected?
      Kernel.pbMessage(_INTL("No hay conexion con el servidor multijugador."))
      return
    end
    players = online_players(true)
    if players.length == 0
      Kernel.pbMessage(_INTL("No hay jugadores conectados todavia."))
      return
    end
    commands = []
    for player in players
      suffix = ($game_map && player.remote_map_id == $game_map.map_id) ? "" : _INTL(" (otro mapa)")
      commands.push(player.remote_name.to_s + suffix)
    end
    commands.push(_INTL("Cancelar"))
    cmd = Kernel.pbMessage(_INTL("Hacer TP a que jugador?"), commands, commands.length)
    return if cmd < 0 || cmd >= players.length
    teleport_to_player(players[cmd])
  end

  def self.open_battle_menu
    if !enabled? || !client.connected?
      Kernel.pbMessage(_INTL("No hay conexion con el servidor multijugador."))
      return
    end
    players = online_players(true)
    if players.length == 0
      Kernel.pbMessage(_INTL("No hay jugadores conectados todavia."))
      return
    end
    commands = players.collect { |player| player.remote_name.to_s }
    commands.push(_INTL("Cancelar"))
    cmd = Kernel.pbMessage(_INTL("A que jugador quieres retar?"), commands, commands.length)
    return if cmd < 0 || cmd >= players.length
    SebiPvpRules.open_challenge_menu(players[cmd]) if defined?(SebiPvpRules)
  end

  def self.open_player_menu(player)
    return if !player
    return if !enabled?
    if !client.connected?
      Kernel.pbMessage(_INTL("No hay conexion con el servidor multijugador."))
      return
    end
    begin
      @busy = true
      commands = []
      actions = []
      commands.push(_INTL("TP a este jugador"))
      actions.push(:teleport)
      if @follow_player_id && @follow_player_id.to_s == player.remote_id.to_s
        commands.push(_INTL("Dejar de seguir"))
        actions.push(:stop_follow)
      else
        commands.push(_INTL("Seguir a este jugador"))
        actions.push(:follow)
      end
      if player.respond_to?(:busy_state) && player.busy_state == "battle"
        commands.push(_INTL("Espectar combate"))
        actions.push(:spectate)
      end
      commands.push(_INTL("Intercambiar Pokemon"))
      actions.push(:trade)
      commands.push(_INTL("Combatir"))
      actions.push(:battle)
      commands.push(_INTL("Cancelar"))
      actions.push(:cancel)
      cmd = Kernel.pbMessage(_INTL("Que quieres hacer con {1}?", player.remote_name), commands, commands.length)
      action = (cmd >= 0 && cmd < actions.length) ? actions[cmd] : :cancel
      case action
      when :teleport
        @busy = false
        teleport_to_player(player)
      when :follow
        @busy = false
        follow_player(player)
      when :stop_follow
        @busy = false
        stop_following
      when :spectate
        @busy = false
        SebiBattleSpectator.request(player) if defined?(SebiBattleSpectator)
      when :trade
        request_action(player, "trade", "single")
      when :battle
        @busy = false
        SebiPvpRules.open_challenge_menu(player) if defined?(SebiPvpRules)
      end
    ensure
      @busy = false
    end
  end

  def self.teleport_to_player(player, show_message = true, keep_distance = false)
    if !player
      Kernel.pbMessage(_INTL("No se pudo encontrar ese jugador.")) if show_message
      return
    end
    if !$game_player || !$game_map || !$game_temp
      Kernel.pbMessage(_INTL("No hay partida cargada para hacer TP.")) if show_message
      return
    end
    map_id = player.remote_map_id.to_i
    x = player.x.to_i
    y = player.y.to_i
    direction = player.direction.to_i
    direction = 2 if direction != 2 && direction != 4 && direction != 6 && direction != 8
    if keep_distance
      target_x = x + (direction == 4 ? 1 : direction == 6 ? -1 : 0)
      target_y = y + (direction == 8 ? 1 : direction == 2 ? -1 : 0)
      if target_x >= 0 && target_y >= 0
        x = target_x
        y = target_y
      end
    end
    if map_id <= 0
      Kernel.pbMessage(_INTL("Ese jugador no tiene mapa valido todavia.")) if show_message
      return
    end
    if $game_map && $game_map.map_id == map_id
      $game_player.moveto(x, y)
      $game_player.direction = direction if $game_player.respond_to?(:direction=)
      $game_player.center(x, y) if $game_player.respond_to?(:center)
    else
      $game_temp.player_new_map_id = map_id
      $game_temp.player_new_x = x
      $game_temp.player_new_y = y
      $game_temp.player_new_direction = direction
      $game_temp.player_transferring = true
      private_scene_methods = $scene ? $scene.private_methods : []
      if $scene && ($scene.respond_to?(:transfer_player) || private_scene_methods.include?("transfer_player") || private_scene_methods.include?(:transfer_player))
        $scene.send(:transfer_player)
      end
    end
    Kernel.pbMessage(_INTL("TP realizado a {1} en mapa {2}, X {3}, Y {4}.", player.remote_name, map_id, x, y)) if show_message
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo hacer TP a ese jugador: {1}", $!.message.to_s)) if show_message
  end

  def self.open_follow_menu
    if !enabled? || !client.connected?
      Kernel.pbMessage(_INTL("No hay conexion con el servidor multijugador."))
      return
    end
    players = online_players(true)
    if players.length == 0
      Kernel.pbMessage(_INTL("No hay jugadores conectados todavia."))
      return
    end
    commands = []
    for player in players
      commands.push(player.remote_name.to_s)
    end
    commands.push(_INTL("Cancelar"))
    cmd = Kernel.pbMessage(_INTL("A que jugador quieres seguir?"), commands, commands.length)
    return if cmd < 0 || cmd >= players.length
    follow_player(players[cmd])
  end

  def self.follow_player(player)
    return if !player
    @follow_player_id = player.remote_id.to_s
    @follow_transfer_frame = -9999
    @follow_started_frame = Graphics.frame_count rescue 0
    request_close_sebilink_menu
    Kernel.pbMessage(_INTL("Ahora sigues automaticamente a {1}. Pulsa el boton B para dejar de seguir.", player.remote_name))
  rescue Exception
  end

  def self.stop_following(show_message = true)
    was_following = @follow_player_id
    @follow_player_id = nil
    Kernel.pbMessage(_INTL("Has dejado de seguir al jugador.")) if show_message && was_following
  rescue Exception
  end

  def self.following_player
    return nil if !@follow_player_id || !@players
    return @players[@follow_player_id.to_s]
  rescue Exception
    return nil
  end

  def self.update_follow_player
    return if !@follow_player_id
    player = following_player
    if !player
      stop_following(false)
      return
    end
    return if @busy
    return if !$game_player || !$game_map || !$game_temp
    return if local_busy_state != "map"
    return if $game_temp.message_window_showing || $game_temp.player_transferring
    begin
      return if pbMapInterpreterRunning?
    rescue Exception
    end
    begin
      return if $game_player.moving?
    rescue Exception
    end
    if player.remote_map_id.to_i != $game_map.map_id.to_i
      frame = Graphics.frame_count rescue 0
      return if frame - (@follow_transfer_frame || -9999) < 180
      @follow_transfer_frame = frame
      teleport_to_player(player, false, true)
      return
    end
    dx = player.x.to_i - $game_player.x.to_i
    dy = player.y.to_i - $game_player.y.to_i
    return if dx.abs + dy.abs <= 1
    if dx.abs >= dy.abs
      dx > 0 ? $game_player.move_right : $game_player.move_left
    else
      dy > 0 ? $game_player.move_down : $game_player.move_up
    end
  rescue Exception
    log("follow update failed: " + $!.class.to_s + ": " + $!.message.to_s)
  end

  def self.update_follow_cancel_input
    return if !@follow_player_id
    return if @busy
    return if !$game_temp || !$game_player || !$game_map
    return if local_busy_state != "map"
    return if $game_temp.message_window_showing || $game_temp.player_transferring
    frame = Graphics.frame_count rescue 0
    return if frame - (@follow_started_frame || -9999) < 45
    return if frame - (@follow_cancel_frame || -9999) < 15
    triggered = defined?(SebiControls) ? SebiControls.button_b_trigger? : Input.trigger?(Input::B)
    return if !triggered
    @follow_cancel_frame = frame
    player = following_player
    name = player ? player.remote_name.to_s : _INTL("el jugador")
    if Kernel.pbConfirmMessage(_INTL("Seguro que quieres dejar de seguir a {1}?", name))
      stop_following
    end
  rescue Exception
  end

  def self.toggle_shared_marker(region, x, y, show_message = true)
    connected = enabled? && client && client.connected? && client.client_id
    own_id = connected ? client.client_id.to_s : "local"
    marker = @markers ? @markers[own_id] : nil
    if marker && marker[:region].to_i == region.to_i &&
       marker[:x].to_i == x.to_i && marker[:y].to_i == y.to_i
      clear_shared_marker(show_message)
      return
    end
    receive_marker(own_id, region, x, y, local_name)
    client.send_marker(region, x, y, local_name) if connected
    if show_message
      if connected
        Kernel.pbMessage(_INTL("Punto compartido con todos los jugadores de la sala. Desaparecera tras 1 minuto."))
      else
        Kernel.pbMessage(_INTL("Punto marcado en tu mapa. Desaparecera tras 1 minuto."))
      end
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo marcar el punto.")) if show_message
  end

  def self.clear_shared_marker(show_message = true)
    connected = enabled? && client && client.connected?
    own_id = client.client_id.to_s rescue ""
    clear_received_marker(own_id) if own_id != ""
    clear_received_marker("local")
    client.clear_marker if connected
    Kernel.pbMessage(_INTL("Tu marcador se ha borrado.")) if show_message
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo borrar el marcador.")) if show_message
  end

  def self.open_marker_menu
    Kernel.pbMessage(_INTL("Abre el mapa regional normal, mueve el cursor y pulsa el boton X del juego para marcar un punto. Si estas en una sala tambien se compartira. Desaparece tras 1 minuto."))
  end

  def self.open_spectator_menu
    if !enabled? || !client.connected?
      Kernel.pbMessage(_INTL("No hay conexion con el servidor multijugador."))
      return
    end
    players = []
    for player in online_players(true)
      players.push(player) if player.respond_to?(:busy_state) && player.busy_state == "battle"
    end
    if players.length == 0
      Kernel.pbMessage(_INTL("No hay ningun jugador conectado en combate ahora mismo."))
      return
    end
    commands = players.collect { |player| player.remote_name.to_s }
    commands.push(_INTL("Cancelar"))
    cmd = Kernel.pbMessage(_INTL("Que combate quieres espectar?"), commands, commands.length)
    return if cmd < 0 || cmd >= players.length
    SebiBattleSpectator.request(players[cmd]) if defined?(SebiBattleSpectator)
  end

  def self.request_action(player, action, mode, requested_rules = nil)
    if @sessions && @sessions.length > 0
      Kernel.pbMessage(_INTL("Ya tienes una solicitud o sesion multijugador pendiente."))
      return
    end
    token = make_token
    rules = (action == "battle" && defined?(SebiPvpRules)) ? SebiPvpRules.normalize_rules(requested_rules || SebiPvpRules.current_rules) : nil
    @sessions[token] = {
      :token => token,
      :remote_id => player.remote_id,
      :remote_name => player.remote_name,
      :action => action,
      :mode => mode,
      :role => "requester",
      :rules => rules
    }
    fields = [
      token,
      action,
      mode,
      escape(local_name)
    ]
    fields.push(SebiPvpRules.encode(rules)) if rules && defined?(SebiPvpRules)
    pvp_log("send REQ action=" + action.to_s + " mode=" + mode.to_s, @sessions[token])
    client.send_direct(player.remote_id, "REQ", fields)
    request_close_sebilink_menu if action.to_s == "battle"
    Kernel.pbMessage(_INTL("Solicitud de {1} enviada a {2}.", action_label(action, mode), player.remote_name)) if action.to_s != "battle"
  end

  def self.process_direct_messages
    return if @direct_messages.length == 0
    if !safe_to_open_ui?
      message = @direct_messages[0]
      if message && message[1].to_s == "REQ"
        @direct_messages.shift
        send_request_denied(message[0], message[2], blocking_request_reason || _INTL("no puede responder ahora"))
      end
      return
    end
    message = @direct_messages.shift
    from_id = message[0]
    type = message[1]
    fields = message[2]
    pvp_log("process direct type=" + type.to_s + " from=" + from_id.to_s) if type.to_s == "REQ" || type.to_s == "RES" || type.to_s == "CANCEL"
    case type
    when "REQ"
      handle_request(from_id, fields)
    when "RES"
      handle_response(from_id, fields)
    when "TRADEOFFER"
      handle_trade_offer(from_id, fields)
    when "BATTLEPARTY"
      handle_battle_party(from_id, fields)
    when "CANCEL"
      handle_cancel(from_id, fields)
    end
  end

  def self.handle_request(from_id, fields)
    token = fields[0].to_s
    action = fields[1].to_s
    mode = fields[2].to_s
    name = unescape(fields[3].to_s)
    rules = (action == "battle" && defined?(SebiPvpRules)) ? SebiPvpRules.decode(fields[4].to_s) : nil
    if @sessions[token]
      return
    end
    reason = blocking_request_reason
    if reason
      pvp_log("deny REQ reason=" + reason.to_s)
      send_request_denied(from_id, fields, reason)
      return
    end
    text = _INTL("{1} quiere iniciar un {2}. Aceptas?", name, action_label(action, mode))
    text += "\n" + SebiPvpRules.summary(rules) if rules && defined?(SebiPvpRules)
    accepted = Kernel.pbConfirmMessage(text)
    if accepted
      local_rules = rules
      if action == "battle" && rules && rules["source"].to_s == "saved" && defined?(SebiSavedTeams)
        team_name = SebiSavedTeams.choose_team_name(_INTL("Elige tu equipo guardado para este combate."))
        if !team_name
          pvp_log("rejected REQ no saved team token=" + token.to_s)
          client.send_direct(from_id, "RES", [token, "no", action, mode, escape(local_name)])
          return
        end
        local_rules = rules.clone
        local_rules["saved_team"] = team_name
      end
      @sessions[token] = {
        :token => token,
        :remote_id => from_id,
        :remote_name => name,
        :action => action,
        :mode => mode,
        :role => "receiver",
        :rules => local_rules
      }
      response = [token, "yes", action, mode, escape(local_name)]
      response.push(fields[4].to_s) if rules && defined?(SebiPvpRules)
      pvp_log("accepted REQ send RES", @sessions[token])
      client.send_direct(from_id, "RES", response)
      start_session_flow(token)
    else
      pvp_log("rejected REQ token=" + token.to_s)
      client.send_direct(from_id, "RES", [token, "no", action, mode, escape(local_name)])
    end
  end

  def self.handle_response(from_id, fields)
    token = fields[0].to_s
    answer = fields[1].to_s
    action = fields[2].to_s
    mode = fields[3].to_s
    name = unescape(fields[4].to_s)
    session = @sessions[token]
    return if !session
    session[:remote_name] = name if name && name != ""
    if answer != "yes"
      reason = fields[5] ? unescape(fields[5].to_s) : ""
      pvp_log("received RES answer=" + answer.to_s + " reason=" + reason.to_s, session)
      if answer == "busy" && reason != ""
        Kernel.pbMessage(_INTL("{1} no puede aceptar ahora: {2}.", session[:remote_name], reason))
      elsif answer == "busy"
        Kernel.pbMessage(_INTL("{1} no puede aceptar ahora.", session[:remote_name]))
      else
        Kernel.pbMessage(_INTL("{1} ha rechazado la solicitud.", session[:remote_name]))
      end
      @sessions.delete(token)
      return
    end
    session[:action] = action
    session[:mode] = mode
    if action == "battle" && defined?(SebiPvpRules) && fields[5]
      session[:rules] = SebiPvpRules.decode(fields[5].to_s)
    end
    pvp_log("received RES yes action=" + action.to_s + " mode=" + mode.to_s, session)
    start_session_flow(token)
  end

  def self.handle_cancel(from_id, fields)
    token = fields[0].to_s
    session = @sessions[token]
    pvp_log("received CANCEL from=" + from_id.to_s, session)
    Kernel.pbMessage(_INTL("La sesion multijugador se ha cancelado.")) if session
    @sessions.delete(token)
    @pending_session_starts.delete(token) if @pending_session_starts
  end

  def self.start_session_flow(token)
    queue_session_start(token)
  end

  def self.queue_session_start(token)
    session = @sessions[token]
    return if !session || session[:started]
    @pending_session_starts = [] if !@pending_session_starts
    return if @pending_session_starts.include?(token)
    @pending_session_starts.push(token)
    pvp_log("queued session start", session)
  rescue Exception
  end

  def self.process_pending_session_starts
    return if @session_start_running
    return if !@pending_session_starts || @pending_session_starts.length == 0
    return if !safe_to_open_ui?
    token = @pending_session_starts.shift
    session = @sessions[token]
    return if !session || session[:started]
    @session_start_running = true
    begin
      session[:started] = true
      pvp_log("start queued session action=" + session[:action].to_s, session)
      if session[:action] == "trade"
        start_trade_flow(token)
      elsif session[:action] == "battle"
        start_battle_flow(token)
      end
    ensure
      @session_start_running = false
    end
  end

  def self.cancel_session(token, message = nil)
    session = @sessions[token]
    if session
      client.send_direct(session[:remote_id], "CANCEL", [token, escape(message.to_s)])
      @sessions.delete(token)
    end
    begin
      @pending_session_starts.delete(token) if @pending_session_starts
    rescue Exception
    end
    Kernel.pbMessage(message) if message && message != ""
  end

  def self.encode_object(object)
    return Marshal.dump(object).unpack("H*")[0]
  end

  def self.decode_object(hex)
    return Marshal.load([hex.to_s].pack("H*"))
  end

  def self.choose_trade_index
    scene = PokemonScreen_Scene.new
    screen = PokemonScreen.new(scene, $Trainer.party)
    index = -1
    begin
      screen.pbStartScene(_INTL("Elige el Pokemon que quieres intercambiar."), false)
      index = screen.pbChoosePokemon(_INTL("Elige el Pokemon que quieres intercambiar."))
      screen.pbEndScene
    rescue Exception
      begin
        screen.pbEndScene
      rescue Exception
      end
      raise
    end
    return index
  end

  def self.start_trade_flow(token)
    session = @sessions[token]
    return if !session
    begin
      @busy = true
      index = choose_trade_index
      if index < 0 || index >= $Trainer.party.length || !$Trainer.party[index]
        cancel_session(token, _INTL("Intercambio cancelado."))
        return
      end
      pokemon = $Trainer.party[index]
      session[:local_index] = index
      session[:local_sent] = true
      client.send_direct(session[:remote_id], "TRADEOFFER", [
        token,
        index.to_s,
        escape(pokemon.name),
        encode_object(pokemon)
      ])
      Kernel.pbMessage(_INTL("Esperando al Pokemon de {1}...", session[:remote_name]))
    ensure
      @busy = false
    end
    try_complete_trade(token)
  rescue Exception
    log("trade flow failed: " + $!.class.to_s + ": " + $!.message.to_s)
    @busy = false
    cancel_session(token, _INTL("No se pudo preparar el intercambio."))
  end

  def self.handle_trade_offer(from_id, fields)
    token = fields[0].to_s
    session = @sessions[token]
    return if !session
    session[:remote_offer_index] = fields[1].to_i
    session[:remote_pokemon_name] = unescape(fields[2].to_s)
    session[:remote_pokemon_hex] = fields[3].to_s
    try_complete_trade(token)
  end

  def self.try_complete_trade(token)
    session = @sessions[token]
    return if !session
    return if !session[:local_sent] || !session[:remote_pokemon_hex]
    begin
      @busy = true
      remote_pokemon = decode_object(session[:remote_pokemon_hex])
      index = session[:local_index]
      name = session[:remote_name] || _INTL("Jugador")
      pbStartTrade(index, remote_pokemon, remote_pokemon.name, name, 0)
      Kernel.pbMessage(_INTL("Intercambio completado con {1}.", name))
    rescue Exception
      log("trade complete failed: " + $!.class.to_s + ": " + $!.message.to_s)
      Kernel.pbMessage(_INTL("No se pudo completar el intercambio."))
    ensure
      @busy = false
    end
    @sessions.delete(token)
  end

  def self.start_battle_flow(token)
    session = @sessions[token]
    return if !session
    pvp_log("battle flow begin", session)
    if !$Trainer
      cancel_session(token, _INTL("No tienes Pokemon para combatir."))
      return
    end
    rules = defined?(SebiPvpRules) ? SebiPvpRules.normalize_rules(session[:rules] || SebiPvpRules.current_rules) : nil
    local_party = $Trainer.party
    if defined?(SebiPvpRules)
      pvp_log("prepare local party rules=" + (SebiPvpRules.encode(rules) rescue ""), session)
      local_party, error = SebiPvpRules.prepare_party(rules, session)
      if error || !local_party || local_party.length == 0
        pvp_log("prepare local party failed error=" + (error || "").to_s, session)
        cancel_session(token, error || _INTL("No se pudo preparar tu equipo de combate."))
        return
      end
    end
    if session[:mode] == "double" && party_able_count(local_party) < 2
      cancel_session(token, _INTL("Necesitas al menos dos Pokemon disponibles para un combate doble."))
      return
    end
    session[:rules] = rules
    session[:local_party] = local_party
    if defined?(SebiPvpRules)
      session[:local_source_level] = [
        SebiPvpRules.highest_owned_level,
        SebiPvpRules.party_max_level($Trainer.party)
      ].max
    else
      session[:local_source_level] = 1
    end
    session[:local_sent] = true
    encoded_party = encode_object(local_party)
    legend_log = ""
    if defined?(SebiPvpRules) && rules
      legend_log = " legends=" + SebiPvpRules.party_legend_count(local_party).to_s + "/" + SebiPvpRules.legend_target(rules).to_s
      legend_names = SebiPvpRules.party_legend_names(local_party).to_s
      legend_log += " legend_names=" + (legend_names == "" ? "-" : legend_names)
    end
    pvp_log("send BATTLEPARTY count=" + local_party.length.to_s + legend_log + " bytes=" + encoded_party.length.to_s, session)
    sent = client.send_direct(session[:remote_id], "BATTLEPARTY", [
      token,
      session[:mode].to_s,
      escape(local_name),
      ($Trainer.trainertype rescue 0).to_i,
      encoded_party,
      session[:local_source_level].to_i
    ])
    pvp_log("send BATTLEPARTY result=" + sent.to_s, session)
    if !session[:remote_party_hex] && !wait_for_pvp_party(session)
      pvp_log("wait BATTLEPARTY timeout", session)
      Kernel.pbMessage(_INTL("No se recibio el equipo de {1}.", session[:remote_name]))
      @sessions.delete(token)
      return
    end
    pvp_log("battle party exchange complete", session)
    try_complete_battle(token)
  rescue Exception
    log("battle flow failed: " + $!.class.to_s + ": " + $!.message.to_s)
    pvp_log("battle flow exception " + $!.class.to_s + ": " + $!.message.to_s, session)
    cancel_session(token, _INTL("No se pudo preparar el combate."))
  end

  def self.handle_battle_party(from_id, fields)
    token = fields[0].to_s
    session = @sessions[token]
    return if !session
    apply_battle_party_fields(session, fields)
    try_complete_battle(token)
  end

  def self.apply_battle_party_fields(session, fields)
    return if !session || !fields
    session[:mode] = fields[1].to_s if fields[1]
    session[:remote_name] = unescape(fields[2].to_s) if fields[2]
    session[:remote_trainertype] = fields[3].to_i
    session[:remote_party_hex] = fields[4].to_s
    session[:remote_source_level] = fields[5].to_i if fields[5]
    pvp_log("applied remote party bytes=" + session[:remote_party_hex].to_s.length.to_s, session)
  rescue Exception
    log("battle party fields failed: " + $!.class.to_s + ": " + $!.message.to_s)
    pvp_log("battle party fields exception " + $!.class.to_s + ": " + $!.message.to_s, session)
  end

  def self.wait_for_pvp_party(session)
    token = session[:token].to_s
    limit = pvp_wait_limit_frames
    pvp_log("wait BATTLEPARTY begin limit=" + limit.to_s, session)
    while limit > 0
      if @pvp_party_inbox[token]
        entry = @pvp_party_inbox[token]
        @pvp_party_inbox.delete(token)
        fields = entry[1] || []
        apply_battle_party_fields(session, fields)
        pvp_log("wait BATTLEPARTY got", session)
        return true
      end
      begin
        client.read_available
      rescue Exception
      end
      Graphics.update
      Input.update
      limit -= 1
    end
    return false
  end

  def self.party_able_count(party)
    count = 0
    for pkmn in party
      next if !pkmn
      egg = false
      begin
        egg = pkmn.isEgg?
      rescue Exception
      end
      next if egg
      begin
        count += 1 if pkmn.hp > 0
      rescue Exception
        count += 1
      end
    end
    return count
  end

  def self.try_complete_battle(token)
    session = @sessions[token]
    return if !session
    return if !session[:local_sent] || !session[:remote_party_hex]
    return if session[:completing]
    session[:completing] = true
    @busy = true
    begin
      pvp_log("complete battle begin", session)
      remote_party = decode_object(session[:remote_party_hex])
      local_party = session[:local_party] || $Trainer.party
      remote_legend_log = ""
      if defined?(SebiPvpRules) && session[:rules]
        remote_legend_log = " legends=" + SebiPvpRules.party_legend_count(remote_party).to_s + "/" + SebiPvpRules.legend_target(session[:rules]).to_s
        remote_legend_names = SebiPvpRules.party_legend_names(remote_party).to_s
        remote_legend_log += " legend_names=" + (remote_legend_names == "" ? "-" : remote_legend_names)
      end
      pvp_log("decoded remote party count=" + (remote_party ? remote_party.length.to_s : "0") + remote_legend_log, session)
      if defined?(SebiPvpRules) && session[:rules]
        remote_rule_error = SebiPvpRules.validate_generated_party_rules(remote_party, session[:rules])
        if remote_rule_error
          pvp_log("remote party rule validation failed error=" + remote_rule_error.to_s, session)
          cancel_session(token, _INTL("El equipo recibido de {1} no cumple las reglas: {2}", session[:remote_name], remote_rule_error))
          return
        end
      end
      if defined?(SebiPvpRules)
        SebiPvpRules.apply_level_rule(
          local_party,
          remote_party,
          session[:rules],
          session[:local_source_level],
          session[:remote_source_level]
        )
      end
      if session[:mode] == "double" && party_able_count(remote_party) < 2
        Kernel.pbMessage(_INTL("{1} no tiene dos Pokemon disponibles.", session[:remote_name]))
        @sessions.delete(token)
        return
      end
      if defined?(SebiPvpPreview)
        pvp_log("preview begin", session)
        confirmed = SebiPvpPreview.confirm_team(session, local_party, remote_party)
        pvp_log("preview result=" + confirmed.to_s, session)
        if !confirmed
          send_pvp_ready(session, "CANCEL")
          Kernel.pbMessage(_INTL("Combate cancelado antes de confirmar el equipo."))
          @sessions.delete(token)
          return
        end
        send_pvp_ready(session, "READY")
        pvp_log("wait READY begin", session)
        remote_ready = wait_for_pvp_ready(session)
        pvp_log("wait READY result=" + remote_ready.to_s, session)
        if remote_ready != "READY"
          Kernel.pbMessage(_INTL("El rival ha cancelado o no ha confirmado su equipo."))
          @sessions.delete(token)
          return
        end
      elsif defined?(SebiPvpRules)
        Kernel.pbMessage(_INTL("Vista previa del equipo de {1} (orden de salida oculto):\n{2}", session[:remote_name], SebiPvpRules.party_preview_text(remote_party)))
      end
      lead_count = session[:mode] == "double" ? 2 : 1
      pvp_log("choose local lead count=" + lead_count.to_s, session)
      local_leads = defined?(SebiPvpRules) ? SebiPvpRules.choose_lead_indexes(local_party, lead_count) : [0]
      if !local_leads
        send_pvp_lead(session, "CANCEL")
        Kernel.pbMessage(_INTL("Combate cancelado."))
        @sessions.delete(token)
        return
      end
      send_pvp_lead(session, local_leads.join(","))
      pvp_log("wait LEAD begin local=" + local_leads.join(","), session)
      remote_lead_text = wait_for_pvp_lead(session)
      pvp_log("wait LEAD result=" + remote_lead_text.to_s, session)
      if !remote_lead_text || remote_lead_text == "CANCEL"
        Kernel.pbMessage(_INTL("El combate se ha cancelado o se ha perdido la conexion."))
        @sessions.delete(token)
        return
      end
      remote_leads = remote_lead_text.split(",").collect { |value| value.to_i }
      if !defined?(SebiPvpRules) || !SebiPvpRules.valid_lead_indexes?(remote_party, remote_leads, lead_count)
        Kernel.pbMessage(_INTL("No se pudo sincronizar el Pokemon inicial del rival."))
        @sessions.delete(token)
        return
      end
      if defined?(SebiPvpRules)
        local_party = SebiPvpRules.reorder_party(local_party, local_leads)
        remote_party = SebiPvpRules.reorder_party(remote_party, remote_leads)
      end
      pvp_log("start snapshot battle", session)
      start_snapshot_battle(session, remote_party, local_party)
    rescue Exception
      log("battle complete failed: " + $!.class.to_s + ": " + $!.message.to_s)
      pvp_log("complete battle exception " + $!.class.to_s + ": " + $!.message.to_s, session)
      Kernel.pbMessage(_INTL("No se pudo iniciar el combate multijugador."))
    ensure
      @busy = false
      session[:completing] = false if session
    end
    @sessions.delete(token)
  end

  def self.pvp_seed(token, round)
    seed = 0
    token.to_s.each_byte { |b| seed = (seed * 31 + b) & 0x7fffffff }
    return (seed + round.to_i * 1009) & 0x7fffffff
  end

  def self.pvp_wait_limit_frames
    default = 108000
    begin
      default = SebiPvpRules::PVP_WAIT_DEFAULT_FRAMES if defined?(SebiPvpRules) && SebiPvpRules.const_defined?(:PVP_WAIT_DEFAULT_FRAMES)
    rescue Exception
      default = 108000
    end
    limit = config_number("pvp_wait_frames", default)
    limit = default if limit <= 0
    limit = default if limit < default
    return limit
  rescue Exception
    return 108000
  end

  def self.send_pvp_choices(session, round, encoded)
    client.send_direct(session[:remote_id], "PVPCHOICES", [
      session[:token].to_s,
      round.to_s,
      encoded.to_s
    ])
  end

  def self.wait_for_pvp_choices(session, round)
    token = session[:token].to_s
    key = token + ":" + round.to_s
    limit = pvp_wait_limit_frames
    while limit > 0
      if @pvp_choice_inbox[key]
        fields = @pvp_choice_inbox[key]
        @pvp_choice_inbox.delete(key)
        return fields[2].to_s
      end
      begin
        client.read_available
      rescue Exception
      end
      Graphics.update
      Input.update
      limit -= 1
    end
    return nil
  end

  def self.send_pvp_switches(session, round, encoded)
    client.send_direct(session[:remote_id], "PVPSWITCH", [
      session[:token].to_s,
      round.to_s,
      encoded.to_s
    ])
  rescue Exception
    log("pvp switch send failed: " + $!.class.to_s + ": " + $!.message.to_s)
  end

  def self.send_pvp_lead(session, encoded)
    pvp_log("send BATTLELEAD value=" + encoded.to_s, session)
    client.send_direct(session[:remote_id], "BATTLELEAD", [
      session[:token].to_s,
      encoded.to_s
    ])
  rescue Exception
    log("pvp lead send failed: " + $!.class.to_s + ": " + $!.message.to_s)
  end

  def self.send_pvp_ready(session, value)
    pvp_log("send BATTLEREADY value=" + value.to_s, session)
    client.send_direct(session[:remote_id], "BATTLEREADY", [
      session[:token].to_s,
      value.to_s
    ])
  rescue Exception
    log("pvp ready send failed: " + $!.class.to_s + ": " + $!.message.to_s)
  end

  def self.wait_for_pvp_ready(session)
    token = session[:token].to_s
    limit = pvp_wait_limit_frames
    pvp_log("wait BATTLEREADY begin limit=" + limit.to_s, session)
    while limit > 0
      if @pvp_ready_inbox[token]
        fields = @pvp_ready_inbox[token]
        @pvp_ready_inbox.delete(token)
        pvp_log("wait BATTLEREADY got value=" + fields[1].to_s, session)
        return fields[1].to_s
      end
      begin
        client.read_available
      rescue Exception
      end
      Graphics.update
      Input.update
      limit -= 1
    end
    return nil
  end

  def self.wait_for_pvp_lead(session)
    token = session[:token].to_s
    limit = pvp_wait_limit_frames
    pvp_log("wait BATTLELEAD begin limit=" + limit.to_s, session)
    while limit > 0
      if @pvp_lead_inbox[token]
        fields = @pvp_lead_inbox[token]
        @pvp_lead_inbox.delete(token)
        pvp_log("wait BATTLELEAD got value=" + fields[1].to_s, session)
        return fields[1].to_s
      end
      begin
        client.read_available
      rescue Exception
      end
      Graphics.update
      Input.update
      limit -= 1
    end
    return nil
  end

  def self.wait_for_pvp_switches(session, round)
    token = session[:token].to_s
    key = token + ":" + round.to_s
    limit = pvp_wait_limit_frames
    while limit > 0
      if @pvp_switch_inbox[key]
        fields = @pvp_switch_inbox[key]
        @pvp_switch_inbox.delete(key)
        return fields[2].to_s
      end
      begin
        client.read_available
      rescue Exception
      end
      Graphics.update
      Input.update
      limit -= 1
    end
    return nil
  end

  def self.pvp_forfeit_message
    return "FORFEIT"
  end

  def self.start_snapshot_battle(session, remote_party, local_party = nil)
    @busy = true
    local_party_backup = nil
    local_money_backup = nil
    begin
      @pvp_party_inbox = {}
      @pvp_choice_inbox = {}
      @pvp_switch_inbox = {}
      @pvp_lead_inbox = {}
      @pvp_ready_inbox = {}
      name = session[:remote_name] || _INTL("Jugador")
      trainertype = session[:remote_trainertype] || ($Trainer.trainertype rescue 0)
      opponent = PokeBattle_Trainer.new(name, trainertype)
      opponent.setForeignID($Trainer)
      opponent.party = remote_party
      local_party_backup = encode_object($Trainer.party)
      local_money_backup = $Trainer.money
      $Trainer.party = local_party if local_party
      decision = 0
      scene = pbNewBattleScene
      battle = PokeBattle_Battle.new(scene, $Trainer.party, remote_party, $Trainer, opponent)
      battle.fullparty1 = false
      battle.fullparty2 = false
      battle.doublebattle = (session[:mode] == "double") ? battle.pbDoubleBattleAllowed?() : false
      battle.internalbattle = false
      battle.endspeech = _INTL("Buen combate.")
      battle.instance_variable_set("@sebi_pvp_session", session)
      Events.onStartBattle.trigger(nil, nil)
      pbPrepareBattle(battle)
      begin
        trainerbgm = nil
        begin
          trainerbgm = pbGetTrainerBattleBGM(opponent)
        rescue Exception
        end
        begin
          pbBattleAnimation(trainerbgm, opponent.trainertype, opponent.name) {
            pbSceneStandby {
              decision = battle.pbStartBattle(true)
            }
          }
        rescue Exception
          pbSceneStandby {
            decision = battle.pbStartBattle(true)
          }
        end
      ensure
        begin
          $Trainer.party = decode_object(local_party_backup)
          $Trainer.money = local_money_backup
        rescue Exception
        end
        Events.onEndBattle.trigger(nil, decision, true)
        Input.update
      end
      Kernel.pbMessage(_INTL("Combate terminado."))
    ensure
      begin
        $Trainer.party = decode_object(local_party_backup) if local_party_backup
        $Trainer.money = local_money_backup if local_money_backup != nil
      rescue Exception
      end
      @busy = false
    end
  end

  def self.players_for_map(map_id)
    purge_old_players
    list = []
    for player in @players.values
      next if player.remote_map_id != map_id
      next if player.character_name == nil || player.character_name == ""
      next if player.last_seen && Graphics.frame_count - player.last_seen > config_number("hide_after", 600)
      list.push(player)
    end
    return list
  end

  def self.characters_for_map(map_id)
    purge_old_players
    list = []
    for player in @players.values
      for character in player.remote_characters_for_map(map_id)
        next if character.character_name == nil || character.character_name == ""
        next if character.last_seen && Graphics.frame_count - character.last_seen > config_number("hide_after", 600)
        list.push(character)
      end
    end
    return list
  end

  def self.purge_old_players
    hide_after = config_number("hide_after", 600)
    for id in @players.keys
      player = @players[id]
      if !player.last_seen || Graphics.frame_count - player.last_seen > hide_after
        remove_player(id)
      end
    end
  end
end

module SebiLinkOptions
  DATA_IVAR = :@sebi_pokelink_options

  def self.data
    return SebiLinkFileConfig.option_data(DATA_IVAR, {:remote_collisions => true})
  end


  def self.remote_collisions?
    return data[:remote_collisions] ? true : false
  end

  def self.toggle_remote_collisions
    data[:remote_collisions] = !remote_collisions?
    SebiLinkFileConfig.set("remote_collisions", remote_collisions? ? "true" : "false") if defined?(SebiLinkFileConfig)
    if remote_collisions?
      Kernel.pbMessage(_INTL("Colisiones entre jugadores activadas."))
    else
      Kernel.pbMessage(_INTL("Colisiones entre jugadores desactivadas."))
    end
  end
end

module SebiMoveInfo
  def self.safe(default_value = nil)
    return yield
  rescue Exception
    return default_value
  end

  def self.type_name(type)
    return PBTypes.getName(type.to_i).to_s if defined?(PBTypes)
    return ""
  rescue Exception
    return ""
  end

  def self.category_name(category)
    case category.to_i
    when 0
      return "Fisico"
    when 1
      return "Especial"
    when 2
      return "Estado"
    end
    return category.to_s
  rescue Exception
    return ""
  end

  def self.description(id)
    return pbGetMessage(MessageTypes::MoveDescriptions, id.to_i).to_s if defined?(MessageTypes)
    return ""
  rescue Exception
    return ""
  end

  def self.details(id)
    id = id.to_i
    return { "id" => 0, "name" => "", "type" => -1, "typeName" => "", "category" => -1, "categoryName" => "", "power" => 0, "accuracy" => 0, "pp" => 0, "description" => "" } if id <= 0
    data = nil
    data = PBMoveData.new(id) if defined?(PBMoveData)
    type = safe(-1) { data.type.to_i }
    category = safe(-1) { data.category.to_i }
    return {
      "id" => id,
      "name" => (PBMoves.getName(id).to_s rescue ""),
      "type" => type,
      "typeName" => type_name(type),
      "category" => category,
      "categoryName" => category_name(category),
      "power" => safe(0) { data.basedamage.to_i },
      "accuracy" => safe(0) { data.accuracy.to_i },
      "pp" => safe(0) { data.totalpp.to_i },
      "description" => description(id)
    }
  rescue Exception
    return { "id" => id, "name" => "", "type" => -1, "typeName" => "", "category" => -1, "categoryName" => "", "power" => 0, "accuracy" => 0, "pp" => 0, "description" => "" }
  end
end

class SebiLevelSyncScene
  def pbRefresh
  end
end

module SebiCheats
  DATA_IVAR = :@sebi_pokelink_cheats
  REPEL_TOGGLE_KEY = 0x78
  LEVEL_CAP_VANILLA_EXTRA = 2
  LEVEL_CAP_DEFAULT_EXTRA_MIN = 0
  LEVEL_CAP_DEFAULT_EXTRA_MAX = 20
  LEVEL_CAP_CONSTANTS = [
    "LEVELGYM0", "LEVELGYM1", "LEVELGYM2", "LEVELGYM3", "LEVELGYM4",
    "LEVELGYM5", "LEVELGYM6", "LEVELGYM7", "LEVELGYM8", "LEVELGYM9",
    "LEVELGYM10", "LEVELGYM11", "LEVELGYM12"
  ]

  @original_level_caps = {}
  for const_name in LEVEL_CAP_CONSTANTS
    @original_level_caps[const_name] = Object.const_get(const_name.to_sym) if Object.const_defined?(const_name.to_sym)
  end
  @last_level_cap_applied = nil

  def self.const_key(name)
    return name.is_a?(Symbol) ? name : name.to_s.to_sym
  end

  def self.data
    return SebiLinkFileConfig.option_data(DATA_IVAR, {
      :wild_shiny_percent => 10, :level_cap_override => nil,
      :level_cap_default_extra => LEVEL_CAP_VANILLA_EXTRA, :max_repel => false})
  end


  def self.max_level
    return PBExperience::MAXLEVEL if defined?(PBExperience) && PBExperience.const_defined?(:MAXLEVEL)
    return MAXIMUMLEVEL if Object.const_defined?(:MAXIMUMLEVEL)
    return 100
  end

  def self.clamp(value, min_value, max_value)
    value = value.to_i
    value = min_value if value < min_value
    value = max_value if value > max_value
    return value
  end

  def self.wild_shiny_percent
    return clamp(data[:wild_shiny_percent], 0, 100)
  end

  def self.wild_shiny_percent=(value)
    data[:wild_shiny_percent] = clamp(value, 0, 100)
    SebiLinkFileConfig.set("wild_shiny_percent", data[:wild_shiny_percent].to_s) if defined?(SebiLinkFileConfig)
  end

  def self.level_cap_override
    value = data[:level_cap_override]
    return nil if value == nil || value.to_i <= 0
    return clamp(value, 1, max_level)
  end

  def self.level_cap_override=(value)
    data[:level_cap_override] = value == nil ? nil : clamp(value, 1, max_level)
    SebiLinkFileConfig.set("level_cap_override", data[:level_cap_override] ? data[:level_cap_override].to_s : "") if defined?(SebiLinkFileConfig)
    apply_level_cap_override(true)
  end

  def self.restore_level_cap_override(value)
    data[:level_cap_override] = value == nil ? nil : clamp(value, 1, max_level)
    SebiLinkFileConfig.set("level_cap_override", data[:level_cap_override] ? data[:level_cap_override].to_s : "") if defined?(SebiLinkFileConfig)
    apply_level_cap_override(true)
  rescue Exception
  end

  def self.level_cap_default_extra
    return clamp(data[:level_cap_default_extra], LEVEL_CAP_DEFAULT_EXTRA_MIN, LEVEL_CAP_DEFAULT_EXTRA_MAX)
  end

  def self.level_cap_default_extra=(value)
    data[:level_cap_default_extra] = clamp(value, LEVEL_CAP_DEFAULT_EXTRA_MIN, LEVEL_CAP_DEFAULT_EXTRA_MAX)
    SebiLinkFileConfig.set("level_cap_default_extra", data[:level_cap_default_extra].to_s) if defined?(SebiLinkFileConfig)
    apply_level_cap_override(true)
  end

  def self.max_repel?
    return data[:max_repel] ? true : false
  end

  def self.max_repel=(value)
    data[:max_repel] = value ? true : false
    SebiLinkFileConfig.set("max_repel", data[:max_repel] ? "true" : "false") if defined?(SebiLinkFileConfig)
  end

  def self.original_level_cap(const_name)
    return @original_level_caps[const_name] if @original_level_caps.has_key?(const_name)
    return Object.const_get(const_key(const_name)) if Object.const_defined?(const_key(const_name))
    return max_level
  end

  def self.default_story_level_cap(const_name)
    base = original_level_cap(const_name).to_i - LEVEL_CAP_VANILLA_EXTRA
    base = 1 if base < 1
    return clamp(base + level_cap_default_extra, 1, max_level)
  end

  def self.natural_level_cap
    cap = default_story_level_cap("LEVELGYM0")
    for i in 1..12
      switch_name = "SWITCHGYM" + i.to_s
      level_name = "LEVELGYM" + i.to_s
      next if !Object.const_defined?(const_key(switch_name))
      next if !$game_switches
      cap = default_story_level_cap(level_name) if $game_switches[Object.const_get(const_key(switch_name))]
    end
    return clamp(cap, 1, max_level)
  rescue Exception
    return clamp(default_story_level_cap("LEVELGYM0"), 1, max_level)
  end

  def self.current_level_cap
    override = level_cap_override
    return override if override
    return natural_level_cap
  end

  def self.apply_level_cap_override(force = false)
    override = level_cap_override
    marker = override ? [:override, override] : [:natural, level_cap_default_extra]
    return if !force && @last_level_cap_applied == marker
    for const_name in LEVEL_CAP_CONSTANTS
      next if !@original_level_caps.has_key?(const_name)
      value = override ? override : default_story_level_cap(const_name)
      begin
        key = const_key(const_name)
        Object.send(:remove_const, key) if Object.const_defined?(key)
        Object.const_set(key, value)
      rescue Exception
      end
    end
    @last_level_cap_applied = marker
  end

  def self.apply_wild_shiny_roll(pokemon, isroamer = false)
    return if !pokemon || isroamer
    percent = wild_shiny_percent
    if percent <= 0
      set_shiny(pokemon, false)
    elsif percent >= 100
      set_shiny(pokemon, true)
    elsif rand(10000) < percent * 100
      set_shiny(pokemon, true)
    else
      set_shiny(pokemon, false)
    end
  end

  def self.set_shiny(pokemon, value)
    return if !pokemon
    if value
      pokemon.makeShiny if pokemon.respond_to?(:makeShiny)
    else
      pokemon.makeNotShiny if pokemon.respond_to?(:makeNotShiny)
    end
    pokemon.calcStats if pokemon.respond_to?(:calcStats)
  end

  def self.party_label(index, pokemon)
    mark = pokemon.isShiny? ? " *" : ""
    return (index + 1).to_s + ". " + pokemon.name.to_s + " Nv." + pokemon.level.to_s + mark
  end

  def self.choose_party_index(message, shiny_state = nil, exclude_index = nil)
    if !$Trainer || !$Trainer.party || $Trainer.party.length == 0
      Kernel.pbMessage(_INTL("No tienes Pokemon en el equipo."))
      return nil
    end
    commands = []
    indexes = []
    party = $Trainer.party
    for i in 0...party.length
      pokemon = party[i]
      next if !pokemon || pokemon.isEgg?
      next if exclude_index != nil && i == exclude_index
      next if shiny_state == true && !pokemon.isShiny?
      next if shiny_state == false && pokemon.isShiny?
      indexes.push(i)
      commands.push(party_label(i, pokemon))
    end
    if indexes.length == 0
      Kernel.pbMessage(_INTL("No hay ningun Pokemon valido para elegir."))
      return nil
    end
    commands.push(_INTL("Cancelar"))
    cmd = Kernel.pbMessage(message, commands, commands.length)
    return nil if cmd < 0 || cmd >= indexes.length
    return indexes[cmd]
  end

  def self.storage_box_name(box_index)
    name = ""
    begin
      box = $PokemonStorage[box_index] if defined?($PokemonStorage) && $PokemonStorage
      name = box.name.to_s if box && box.respond_to?(:name)
    rescue Exception
      name = ""
    end
    name = _INTL("Caja {1}", box_index + 1) if name == ""
    return name
  end

  def self.pokemon_ref_key(ref)
    return "" if !ref
    return ref["loc"].to_s + ":" + ref["index"].to_i.to_s + ":" + ref["box"].to_i.to_s + ":" + ref["slot"].to_i.to_s
  rescue Exception
    return ""
  end

  def self.pokemon_ref_label(ref)
    pokemon = ref["pokemon"]
    mark = pokemon.isShiny? ? " *" : ""
    if ref["loc"] == "party"
      return _INTL("Equipo {1}: {2} Nv.{3}{4}", ref["index"].to_i + 1, pokemon.name, pokemon.level, mark)
    end
    return _INTL("{1} Slot {2}: {3} Nv.{4}{5}", storage_box_name(ref["box"].to_i), ref["slot"].to_i + 1, pokemon.name, pokemon.level, mark)
  rescue Exception
    return _INTL("Pokemon")
  end

  def self.all_pokemon_refs_for_shiny
    refs = []
    if $Trainer && $Trainer.party
      for i in 0...$Trainer.party.length
        pokemon = $Trainer.party[i]
        next if !pokemon
        refs.push({ "loc" => "party", "index" => i, "box" => -1, "slot" => -1, "pokemon" => pokemon })
      end
    end
    if defined?($PokemonStorage) && $PokemonStorage
      max_boxes = $PokemonStorage.respond_to?(:maxBoxes) ? $PokemonStorage.maxBoxes : (safe([]) { $PokemonStorage.boxes }.length)
      for box in 0...max_boxes
        max_slots = safe(30) { $PokemonStorage.maxPokemon(box) }
        for slot in 0...max_slots
          pokemon = safe(nil) { $PokemonStorage[box, slot] }
          next if !pokemon
          refs.push({ "loc" => "box", "index" => -1, "box" => box, "slot" => slot, "pokemon" => pokemon })
        end
      end
    end
    return refs
  rescue Exception
    return refs || []
  end

  def self.choose_pokemon_ref_for_shiny(message, shiny_state = nil, exclude_ref = nil)
    refs = []
    commands = []
    exclude_key = pokemon_ref_key(exclude_ref)
    for ref in all_pokemon_refs_for_shiny
      pokemon = ref["pokemon"]
      next if !pokemon || (pokemon.respond_to?(:isEgg?) && pokemon.isEgg?)
      next if exclude_key != "" && pokemon_ref_key(ref) == exclude_key
      next if shiny_state == true && !pokemon.isShiny?
      next if shiny_state == false && pokemon.isShiny?
      refs.push(ref)
      commands.push(pokemon_ref_label(ref))
    end
    if refs.length == 0
      Kernel.pbMessage(_INTL("No hay ningun Pokemon valido para elegir."))
      return nil
    end
    commands.push(_INTL("Cancelar"))
    cmd = Kernel.pbMessage(message, commands, commands.length)
    return nil if cmd < 0 || cmd >= refs.length
    return refs[cmd]
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir la lista de Pokemon."))
    return nil
  end

  def self.change_wild_shiny_percent
    params = ChooseNumberParams.new
    params.setRange(0, 100)
    params.setDefaultValue(wild_shiny_percent)
    params.setCancelValue(wild_shiny_percent)
    value = Kernel.pbMessageChooseNumber(_INTL("Porcentaje shiny salvaje (0-100)."), params)
    self.wild_shiny_percent = value
    Kernel.pbMessage(_INTL("Los Pokemon salvajes tendran {1}% de shiny.", wild_shiny_percent))
  end

  def self.transfer_shiny
    source_ref = choose_pokemon_ref_for_shiny(_INTL("Elige el Pokemon shiny que cedera el shiny."), true, nil)
    return if source_ref == nil
    target_ref = choose_pokemon_ref_for_shiny(_INTL("Elige el Pokemon que recibira el shiny."), false, source_ref)
    return if target_ref == nil
    source = source_ref["pokemon"]
    target = target_ref["pokemon"]
    if !Kernel.pbConfirmMessage(_INTL("Mover el shiny de {1} a {2}?", source.name, target.name))
      return
    end
    set_shiny(source, false)
    set_shiny(target, true)
    pbSeenForm(target) if defined?(pbSeenForm)
    Kernel.pbMessage(_INTL("{1} ya no es shiny. {2} ahora es shiny.", source.name, target.name))
  end

  def self.highest_party_level
    highest = 0
    return highest if !$Trainer || !$Trainer.party
    for pokemon in $Trainer.party
      next if !pokemon || pokemon.isEgg?
      highest = pokemon.level if pokemon.level > highest
    end
    return highest
  end

  def self.configure_default_level_cap_extra
    params = ChooseNumberParams.new
    params.setRange(LEVEL_CAP_DEFAULT_EXTRA_MIN, LEVEL_CAP_DEFAULT_EXTRA_MAX)
    params.setDefaultValue(level_cap_default_extra)
    params.setCancelValue(-1)
    value = Kernel.pbMessageChooseNumber(_INTL("Niveles extra sobre el proximo gimnasio. 0 = mismo nivel; 2 = default original."), params).to_i
    return if value < 0
    self.level_cap_default_extra = value
    self.level_cap_override = nil
    Kernel.pbMessage(_INTL("Level cap default: proximo gimnasio +{1}. Cap actual: {2}.", level_cap_default_extra, current_level_cap))
  end

  def self.change_level_cap
    commands = [
      _INTL("Cambiar level cap fijo"),
      _INTL("Default historia (+{1})", level_cap_default_extra),
      _INTL("Cancelar")
    ]
    cmd = Kernel.pbMessage(_INTL("Level cap actual: {1}", current_level_cap), commands, commands.length)
    return if cmd < 0 || cmd >= commands.length - 1
    if cmd == 1
      configure_default_level_cap_extra
      return
    end
    params = ChooseNumberParams.new
    params.setRange(1, max_level)
    params.setDefaultValue(current_level_cap)
    params.setCancelValue(current_level_cap)
    value = Kernel.pbMessageChooseNumber(_INTL("Nuevo level cap (max. {1}).", max_level), params)
    self.level_cap_override = value
    Kernel.pbMessage(_INTL("Level cap cambiado a {1}.", current_level_cap))
  end

  def self.set_level_cap_value(value, show_message = true)
    text = value.to_s.strip.downcase
    if text =~ /^(default|historia|story|natural)\s*\+?\s*(\d+)$/
      self.level_cap_default_extra = $2.to_i
      self.level_cap_override = nil
      message = _INTL("Level cap default: proximo gimnasio +{1}. Cap actual: {2}.", level_cap_default_extra, current_level_cap)
    elsif text == "" || text == "default" || text == "historia" || text == "story" || text == "natural"
      self.level_cap_override = nil
      message = _INTL("Level cap default restaurado: proximo gimnasio +{1}. Cap actual: {2}.", level_cap_default_extra, current_level_cap)
    else
      number = value.to_i
      if number <= 0
        self.level_cap_override = nil
        message = _INTL("Level cap default restaurado: proximo gimnasio +{1}. Cap actual: {2}.", level_cap_default_extra, current_level_cap)
      else
        self.level_cap_override = number
        message = _INTL("Level cap cambiado a {1}.", current_level_cap)
      end
    end
    Kernel.pbMessage(message) if show_message
    return message
  rescue Exception
    message = _INTL("No se pudo cambiar el level cap.")
    Kernel.pbMessage(message) if show_message
    return message
  end

  def self.toggle_max_repel
    self.max_repel = !max_repel?
    if max_repel?
      Kernel.pbMessage(_INTL("Repelente max activado. No habra encuentros salvajes aleatorios."))
    else
      Kernel.pbMessage(_INTL("Repelente max desactivado."))
    end
  end

  def self.raw_key_pressed?(key)
    begin
      if defined?(SebiControls) && SebiControls.respond_to?(:raw_key_press?)
        return SebiControls.raw_key_press?(key)
      end
      @repel_get_async_key_state = Win32API.new("user32", "GetAsyncKeyState", "i", "i") if !@repel_get_async_key_state && defined?(Win32API)
      return false if !@repel_get_async_key_state
      return (@repel_get_async_key_state.call(key.to_i) & 0x8000) != 0
    rescue Exception
      return false
    end
  end

  def self.repel_toggle_triggered?
    triggered = false
    begin
      triggered = true if defined?(Input) && Input.respond_to?(:triggerex?) && Input.triggerex?(REPEL_TOGGLE_KEY)
    rescue Exception
    end
    pressed = raw_key_pressed?(REPEL_TOGGLE_KEY)
    triggered = true if pressed && !@repel_toggle_key_pressed
    @repel_toggle_key_pressed = pressed
    return triggered
  rescue Exception
    @repel_toggle_key_pressed = false
    return false
  end

  def self.handle_repel_shortcut
    return if !repel_toggle_triggered?
    self.max_repel = !max_repel?
    return if defined?(SebiLinkHub) && !SebiLinkHub.safe_to_open?
    if max_repel?
      Kernel.pbMessage(_INTL("Repelente max activado. No habra encuentros salvajes aleatorios."))
    else
      Kernel.pbMessage(_INTL("Repelente max desactivado."))
    end
  rescue Exception
  end

  def self.sacred_ashes_item
    begin
      return getID(PBItems, :Cenizas) if defined?(PBItems) && defined?(getID)
    rescue Exception
    end
    begin
      return PBItems.const_get(:Cenizas) if defined?(PBItems) && PBItems.const_defined?(:Cenizas)
    rescue Exception
    end
    return :Cenizas
  end

  def self.give_sacred_ashes
    if !$PokemonBag
      Kernel.pbMessage(_INTL("No se encontro la mochila."))
      return
    end
    params = ChooseNumberParams.new
    params.setRange(1, 99)
    params.setDefaultValue(clamp(SebiLinkFileConfig.get_int("sacred_ashes_quantity", 2), 1, 99))
    params.setCancelValue(0)
    quantity = Kernel.pbMessageChooseNumber(_INTL("Cantidad de Cenizas Sagradas (1-99)."), params)
    return if quantity <= 0
    SebiLinkFileConfig.set("sacred_ashes_quantity", quantity)
    item = sacred_ashes_item
    if Kernel.pbReceiveItem(item, quantity)
      Kernel.pbMessage(_INTL("Las Cenizas Sagradas pueden revivir incluso en Nuzlocke."))
    else
      Kernel.pbMessage(_INTL("No se pudieron guardar las Cenizas Sagradas."))
    end
  end

  def self.give_sacred_ashes_quantity(quantity, show_message = true)
    if !$PokemonBag
      message = _INTL("No se encontro la mochila.")
      Kernel.pbMessage(message) if show_message
      return false
    end
    quantity = clamp(quantity.to_i, 1, 999)
    SebiLinkFileConfig.set("sacred_ashes_quantity", quantity)
    item = sacred_ashes_item
    ok = $PokemonBag.pbStoreItem(item, quantity)
    if ok
      message = _INTL("Recibidas {1} Cenizas Sagradas.", quantity)
    else
      message = _INTL("No se pudieron guardar las Cenizas Sagradas.")
    end
    Kernel.pbMessage(message) if show_message
    return ok
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudieron entregar las Cenizas Sagradas.")) if show_message
    return false
  end

  def self.set_wild_shiny_percent_value(value, show_message = true)
    self.wild_shiny_percent = value.to_i
    message = _INTL("Los Pokemon salvajes tendran {1}% de shiny.", wild_shiny_percent)
    Kernel.pbMessage(message) if show_message
    return message
  rescue Exception
    message = _INTL("No se pudo cambiar el porcentaje shiny.")
    Kernel.pbMessage(message) if show_message
    return message
  end

  def self.learn_level_moves(pokemon, old_level, new_level)
    return [] if !pokemon.respond_to?(:getMoveList)
    list = pokemon.getMoveList
    learned = []
    known = {}
    begin
      for i in 0...4
        move_id = pokemon.moves[i].id.to_i
        known[move_id] = true if move_id > 0
      end
    rescue Exception
    end
    seen = {}
    for entry in list
      next if !entry || entry.length < 2
      level = entry[0]
      move = entry[1]
      if move.to_i > 0 && (level > old_level || old_level == 1) && level <= new_level && !known[move.to_i] && !seen[move.to_i]
        detail = defined?(SebiMoveInfo) ? SebiMoveInfo.details(move.to_i) : { "id" => move.to_i, "name" => "" }
        detail["level"] = level.to_i
        learned.push(detail)
        seen[move.to_i] = true
      end
    end
    return learned
  rescue Exception
    return []
  end

  def self.current_move_details(pokemon)
    ret = []
    for i in 0...4
      move_id = 0
      pp = 0
      ppup = 0
      begin
        move = pokemon.moves[i]
        move_id = move.id.to_i if move
        pp = move.pp.to_i if move && move.respond_to?(:pp)
        ppup = move.ppup.to_i if move && move.respond_to?(:ppup)
      rescue Exception
      end
      detail = defined?(SebiMoveInfo) ? SebiMoveInfo.details(move_id) : { "id" => move_id, "name" => "" }
      detail["slot"] = i
      detail["currentPp"] = pp
      detail["ppup"] = ppup
      ret.push(detail)
    end
    return ret
  rescue Exception
    return []
  end

  def self.auto_fill_empty_level_moves(pokemon, learned)
    return if !pokemon || !learned
    learned.each do |detail|
      move_id = detail["id"].to_i
      next if move_id <= 0
      begin
        next if pokemon.hasMove?(move_id)
      rescue Exception
      end
      empty = -1
      for i in 0...4
        begin
          if !pokemon.moves[i] || pokemon.moves[i].id.to_i <= 0
            empty = i
            break
          end
        rescue Exception
        end
      end
      break if empty < 0
      pokemon.moves[empty] = PBMove.new(move_id) if defined?(PBMove)
      detail["autoLearned"] = true
    end
  rescue Exception
  end

  def self.review_entry_for(pokemon, ref, old_level, new_level, learned)
    ref ||= {}
    return {
      "name" => (pokemon.name.to_s rescue ""),
      "species" => (pokemon.species.to_i rescue 0),
      "speciesName" => (PBSpecies.getName(pokemon.species).to_s rescue ""),
      "form" => (pokemon.form.to_i rescue 0),
      "shiny" => ((pokemon.isShiny? ? true : false) rescue false),
      "oldLevel" => old_level.to_i,
      "newLevel" => new_level.to_i,
      "loc" => ref["loc"].to_s,
      "index" => ref["index"].to_i,
      "box" => ref["box"].to_i,
      "slot" => ref["slot"].to_i,
      "learnedMoves" => learned || [],
      "currentMoves" => current_move_details(pokemon)
    }
  rescue Exception
    return nil
  end

  def self.try_evolution(pokemon)
    return if !defined?(pbCheckEvolution)
    newspecies = pbCheckEvolution(pokemon)
    return if !newspecies || newspecies <= 0
    pbFadeOutInWithMusic(99999) do
      evo = PokemonEvolutionScene.new
      evo.pbStartScreen(pokemon, newspecies)
      evo.pbEvolution
      evo.pbEndScreen
    end
  rescue Exception
  end

  def self.raise_pokemon_to_level(pokemon, target_level, ref = nil)
    return false if !pokemon || pokemon.isEgg?
    return false if pokemon.level >= target_level
    old_level = pokemon.level
    old_total_hp = pokemon.totalhp
    old_hp = pokemon.hp
    learned = learn_level_moves(pokemon, old_level, target_level)
    pokemon.level = target_level
    pokemon.changeHappiness("level up") if pokemon.respond_to?(:changeHappiness)
    pokemon.calcStats
    if old_hp > 0
      hp_gain = pokemon.totalhp - old_total_hp
      hp_gain = 0 if hp_gain < 0
      pokemon.hp = [pokemon.totalhp, old_hp + hp_gain].min
    end
    auto_fill_empty_level_moves(pokemon, learned)
    try_evolution(pokemon)
    return review_entry_for(pokemon, ref, old_level, target_level, learned)
  end

  def self.raise_pokemon_to_level_default(pokemon, target_level)
    return false if !pokemon || pokemon.isEgg?
    return false if pokemon.level >= target_level
    old_level = pokemon.level
    if defined?(pbChangeLevel)
      scene = SebiLevelSyncScene.new
      pbChangeLevel(pokemon, target_level, scene)
    else
      while pokemon.level < target_level
        previous = pokemon.level
        pokemon.level += 1
        pokemon.changeHappiness("level up") if pokemon.respond_to?(:changeHappiness)
        pokemon.calcStats if pokemon.respond_to?(:calcStats)
        if pokemon.respond_to?(:getMoveList) && defined?(pbLearnMove)
          for entry in pokemon.getMoveList
            next if !entry || entry.length < 2
            next if entry[0].to_i <= previous || entry[0].to_i > pokemon.level
            pbLearnMove(pokemon, entry[1], true)
          end
        end
      end
      try_evolution(pokemon)
    end
    return pokemon.level > old_level
  rescue Exception
    return false
  end

  def self.choose_level_sync_mode
    commands = [_INTL("Default"), _INTL("Rapidin")]
    cmd = Kernel.pbMessage(_INTL("Como quieres subir los niveles?"), commands, commands.length)
    return nil if cmd < 0 || cmd >= commands.length
    return :default if cmd == 0
    return :rapidin
  rescue Exception
    return :rapidin
  end

  def self.normalize_level_sync_mode(mode)
    return choose_level_sync_mode if mode == nil
    text = mode.to_s.downcase
    return :default if text == "default" || text == "normal" || text == "vanilla"
    return :rapidin if text == "rapidin" || text == "rapido" || text == "fast"
    return choose_level_sync_mode
  rescue Exception
    return :rapidin
  end

  def self.offer_level_review(results)
    return if !results || results.length == 0
    learned_count = 0
    results.each do |entry|
      learned_count += (entry["learnedMoves"] || []).length if entry
    end
    return if learned_count <= 0
    if Kernel.pbConfirmMessage(_INTL("Hay Pokemon que han aprendido movimientos nuevos. Quieres verlos?"))
      if defined?(SebiLevelReview)
        opened = SebiLevelReview.open(results)
        Kernel.pbMessage(_INTL("No se pudo abrir la pantalla de movimientos.")) if !opened
      else
        Kernel.pbMessage(_INTL("La pantalla de movimientos no esta disponible."))
      end
    end
  rescue Exception
  end

  def self.equalize_party_levels(mode = nil)
    preserved_level_cap = level_cap_override
    begin
      mode = normalize_level_sync_mode(mode)
      return if !mode
      if !$Trainer || !$Trainer.party || $Trainer.party.length == 0
        Kernel.pbMessage(_INTL("No tienes Pokemon en el equipo."))
        return
      end
      highest = highest_party_level
      if highest <= 0
        Kernel.pbMessage(_INTL("No hay Pokemon validos para subir."))
        return
      end
      target = [highest, current_level_cap].min
      changed = 0
      results = []
      for i in 0...$Trainer.party.length
        pokemon = $Trainer.party[i]
        if mode == :default
          result = raise_pokemon_to_level_default(pokemon, target)
          changed += 1 if result
        else
          result = raise_pokemon_to_level(pokemon, target, { "loc" => "party", "index" => i, "box" => -1, "slot" => -1 })
          if result
            changed += 1
            results.push(result)
          end
        end
      end
      if changed == 0
        Kernel.pbMessage(_INTL("Tu equipo ya esta al nivel {1}.", target))
      else
        Kernel.pbMessage(_INTL("{1} Pokemon del equipo fueron subidos al nivel {2}.", changed, target))
        offer_level_review(results) if mode == :rapidin
      end
    ensure
      restore_level_cap_override(preserved_level_cap)
    end
  end

  def self.highest_storage_level(storage = nil)
    storage = $PokemonStorage if !storage && defined?($PokemonStorage)
    highest = 0
    return highest if !storage || !storage.respond_to?(:boxes)
    for box in storage.boxes
      next if !box
      box.each do |pokemon|
        next if !pokemon || pokemon.isEgg?
        highest = pokemon.level if pokemon.level > highest
      end
    end
    return highest
  rescue Exception
    return 0
  end

  def self.highest_box_level(storage = nil, box_index = nil)
    storage = $PokemonStorage if !storage && defined?($PokemonStorage)
    return 0 if !storage || !storage.respond_to?(:boxes)
    box_index = storage.currentBox if box_index == nil && storage.respond_to?(:currentBox)
    return 0 if box_index == nil || box_index < 0 || box_index >= storage.boxes.length
    box = storage.boxes[box_index]
    highest = 0
    return highest if !box
    box.each do |pokemon|
      next if !pokemon || pokemon.isEgg?
      highest = pokemon.level if pokemon.level > highest
    end
    return highest
  rescue Exception
    return 0
  end

  def self.equalize_storage_levels(storage = nil, mode = nil)
    preserved_level_cap = level_cap_override
    begin
      mode = normalize_level_sync_mode(mode)
      return if !mode
      storage = $PokemonStorage if !storage && defined?($PokemonStorage)
      if !storage || !storage.respond_to?(:boxes)
        Kernel.pbMessage(_INTL("No se encontro el PC Pokemon."))
        return
      end
      highest = highest_storage_level(storage)
      if highest <= 0
        Kernel.pbMessage(_INTL("No hay Pokemon validos en el PC."))
        return
      end
      target = [highest, current_level_cap].min
      changed = 0
      results = []
      for box_index in 0...storage.boxes.length
        box = storage.boxes[box_index]
        next if !box
        for slot in 0...box.length
          pokemon = box[slot]
          if mode == :default
            result = raise_pokemon_to_level_default(pokemon, target)
            changed += 1 if result
          else
            result = raise_pokemon_to_level(pokemon, target, { "loc" => "box", "index" => -1, "box" => box_index, "slot" => slot })
            if result
              changed += 1
              results.push(result)
            end
          end
        end
      end
      if changed == 0
        Kernel.pbMessage(_INTL("Los Pokemon del PC ya estan al nivel {1}.", target))
      else
        Kernel.pbMessage(_INTL("{1} Pokemon del PC fueron subidos al nivel {2}.", changed, target))
        offer_level_review(results) if mode == :rapidin
      end
    rescue Exception
      Kernel.pbMessage(_INTL("No se pudo igualar el nivel del PC."))
    ensure
      restore_level_cap_override(preserved_level_cap)
    end
  end

  def self.equalize_current_box_levels(storage = nil, mode = nil)
    preserved_level_cap = level_cap_override
    begin
      mode = normalize_level_sync_mode(mode)
      return if !mode
      storage = $PokemonStorage if !storage && defined?($PokemonStorage)
      if !storage || !storage.respond_to?(:boxes) || !storage.respond_to?(:currentBox)
        Kernel.pbMessage(_INTL("No se encontro la caja actual del PC."))
        return
      end
      box_index = storage.currentBox
      if box_index == nil || box_index < 0 || box_index >= storage.boxes.length
        Kernel.pbMessage(_INTL("No se encontro la caja actual del PC."))
        return
      end
      party_highest = highest_party_level
      box_highest = highest_box_level(storage, box_index)
      highest = [party_highest, box_highest].max
      if highest <= 0
        Kernel.pbMessage(_INTL("No hay Pokemon validos para comparar."))
        return
      end
      target = [highest, current_level_cap].min
      changed = 0
      box = storage.boxes[box_index]
      results = []
      if box
        for slot in 0...box.length
          pokemon = box[slot]
          if mode == :default
            result = raise_pokemon_to_level_default(pokemon, target)
            changed += 1 if result
          else
            result = raise_pokemon_to_level(pokemon, target, { "loc" => "box", "index" => -1, "box" => box_index, "slot" => slot })
            if result
              changed += 1
              results.push(result)
            end
          end
        end
      end
      box_name = box && box.respond_to?(:name) ? box.name : _INTL("la caja")
      if changed == 0
        Kernel.pbMessage(_INTL("Los Pokemon de {1} ya estan al nivel {2}.", box_name, target))
      else
        Kernel.pbMessage(_INTL("{1} Pokemon de {2} fueron subidos al nivel {3}.", changed, box_name, target))
        offer_level_review(results) if mode == :rapidin
      end
    rescue Exception
      Kernel.pbMessage(_INTL("No se pudo igualar el nivel de la caja actual."))
    ensure
      restore_level_cap_override(preserved_level_cap)
    end
  end

  def self.open_menu
    apply_level_cap_override
    loop do
      repel = max_repel? ? "ON" : "OFF"
      commands = [
        _INTL("Shiny salvajes: {1}%", wild_shiny_percent),
        _INTL("Mover shiny entre Pokemon"),
        _INTL("Level cap: {1}", current_level_cap),
        _INTL("Repelente max: {1}", repel),
        _INTL("Igualar niveles del equipo"),
        _INTL("Dar Cenizas Sagradas"),
        _INTL("Salir")
      ]
      cmd = Kernel.pbMessage(_INTL("Trucos"), commands, commands.length)
      case cmd
      when 0
        change_wild_shiny_percent
      when 1
        transfer_shiny
      when 2
        change_level_cap
      when 3
        toggle_max_repel
      when 4
        equalize_party_levels
      when 5
        give_sacred_ashes
      else
        break
      end
    end
  end
end

module SebiLevelReview
  COMMAND_POLL_FRAMES = 15
  @last_command_poll_frame = -9999
  @results = []
  @processing_command = false

  def self.base_dir
    return File.expand_path("multiplayer/level-review")
  rescue Exception
    return "multiplayer/level-review"
  end

  def self.runtime_dir
    return SebiLinkPaths.runtime_dir("level-review") if defined?(SebiLinkPaths)
    return File.join(base_dir, "runtime")
  rescue Exception
    return "SebiLinkConfig/level-review/runtime"
  end

  def self.window_path
    return File.join(base_dir, "SebiLevelReview.ps1")
  rescue Exception
    return "multiplayer/level-review/SebiLevelReview.ps1"
  end

  def self.state_path
    return File.join(runtime_dir, "state.json")
  rescue Exception
    return "multiplayer/level-review/runtime/state.json"
  end

  def self.command_path
    return File.join(runtime_dir, "commands.txt")
  rescue Exception
    return "multiplayer/level-review/runtime/commands.txt"
  end

  def self.result_path
    return File.join(runtime_dir, "last_result.json")
  rescue Exception
    return "multiplayer/level-review/runtime/last_result.json"
  end

  def self.ensure_runtime
    if defined?(SebiLinkPaths)
      SebiLinkPaths.migrate_runtime_dir(File.join(base_dir, "runtime"), runtime_dir)
      SebiLinkPaths.ensure_dir(runtime_dir)
    else
      Dir.mkdir(base_dir) if !FileTest.directory?(base_dir)
      Dir.mkdir(runtime_dir) if !FileTest.directory?(runtime_dir)
    end
  rescue Exception
  end

  def self.json(value)
    return SebiSaveEditor.json(value) if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:json)
    return value.to_s
  rescue Exception
    return "null"
  end

  def self.atomic_write(path, text)
    if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:atomic_write)
      SebiSaveEditor.atomic_write(path, text)
      return true
    end
    File.open(path, "wb") { |file| file.write(text.to_s) }
    return true
  rescue Exception
    return false
  end

  def self.write_state
    ensure_runtime
    data = {
      "generatedAt" => Time.now.to_s,
      "results" => @results || []
    }
    atomic_write(state_path, json(data))
  rescue Exception
  end

  def self.quote_arg(value)
    return "\"" + value.to_s.gsub("\"", "") + "\""
  rescue Exception
    return "\"\""
  end

  def self.open_powershell_script(path)
    params = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " + quote_arg(path)
    if defined?(Win32API)
      shell = Win32API.new("shell32", "ShellExecuteA", "LPPPPI", "I")
      result = shell.call(0, "open", "powershell.exe", params, nil, 0)
      return true if result && result.to_i > 32
    end
    system("cmd /c start \"\" powershell.exe " + params)
    return true
  rescue Exception
    SebiVisualMultiplayer.log("No se pudo abrir SebiLevelReview: " + $!.message.to_s) if defined?(SebiVisualMultiplayer)
    return false
  end

  def self.apply_font(bitmap)
    return if !bitmap
    old_size = bitmap.font.size rescue nil
    pbSetSystemFont(bitmap) if defined?(pbSetSystemFont)
    if bitmap.respond_to?(:font) && bitmap.font
      bitmap.font.name = "Power Green Small" if bitmap.font.respond_to?(:name=)
      bitmap.font.size = old_size if old_size && bitmap.font.respond_to?(:size=)
      bitmap.font.bold = false if bitmap.font.respond_to?(:bold=)
    end
  rescue Exception
  end

  def self.draw_text(bitmap, text, x, y, align = 0, base = nil, width = nil, height = nil)
    return if !bitmap
    apply_font(bitmap)
    base = Color.new(248, 248, 248) if !base
    value = width ? fit_text(bitmap, text.to_s, width.to_i) : text.to_s
    shadow = Color.new(0, 0, 0, 0)
    pbDrawTextPositions(bitmap, [[value, x.to_i, y.to_i, align.to_i, base, shadow]])
  rescue Exception
    begin
      old_color = bitmap.font.color rescue nil
      bitmap.font.color = base if bitmap.respond_to?(:font) && bitmap.font && bitmap.font.respond_to?(:color=)
      value = width ? fit_text(bitmap, text.to_s, width.to_i) : text.to_s
      text_width = bitmap.text_size(value).width + 8 rescue 160
      box_width = width ? width.to_i : text_width
      box_height = height ? height.to_i : [((bitmap.font.size rescue 12) + 5), 16].max
      rect_x = x.to_i
      draw_align = 0
      if align.to_i == 1
        rect_x = x.to_i - box_width
        draw_align = 2
      elsif align.to_i == 2
        rect_x = x.to_i - (box_width / 2)
        draw_align = 1
      end
      bitmap.draw_text(Rect.new(rect_x, y.to_i, box_width, box_height), value, draw_align)
      bitmap.font.color = old_color if old_color && bitmap.respond_to?(:font) && bitmap.font && bitmap.font.respond_to?(:color=)
    rescue Exception
    end
  end

  def self.fit_text(bitmap, text, max_width)
    value = text.to_s
    return value if !bitmap || (bitmap.text_size(value).width rescue 0) <= max_width.to_i
    suffix = "..."
    while value.length > 1 && (bitmap.text_size(value + suffix).width rescue 0) > max_width.to_i
      value = value[0, value.length - 1]
    end
    return value + suffix
  rescue Exception
    return text.to_s
  end

  def self.wrap_lines(bitmap, text, max_width, max_lines)
    words = text.to_s.gsub(/\r\n?/, " ").split(/\s+/)
    lines = []
    current = ""
    for word in words
      candidate = current == "" ? word : current + " " + word
      if current != "" && bitmap && (bitmap.text_size(candidate).width rescue 0) > max_width.to_i
        lines.push(current)
        current = word
        break if lines.length >= max_lines.to_i
      else
        current = candidate
      end
    end
    lines.push(current) if current != "" && lines.length < max_lines.to_i
    return lines
  rescue Exception
    return [text.to_s]
  end

  def self.draw_box(bitmap, x, y, width, height, fill, edge)
    bitmap.fill_rect(x.to_i, y.to_i, width.to_i, height.to_i, edge)
    bitmap.fill_rect(x.to_i + 2, y.to_i + 2, width.to_i - 4, height.to_i - 4, fill)
  rescue Exception
  end

  def self.type_bitmap
    @review_type_bitmap = AnimatedBitmap.new(_INTL("Graphics/Pictures/types_ico")) if !@review_type_bitmap
    return @review_type_bitmap.bitmap
  rescue Exception
    return nil
  end

  def self.category_bitmap
    @review_category_bitmap = AnimatedBitmap.new(_INTL("Graphics/Pictures/category")) if !@review_category_bitmap
    return @review_category_bitmap.bitmap
  rescue Exception
    return nil
  end

  def self.draw_sheet_icon(bitmap, sheet, index, x, y, width, height, source_width = 64, source_height = 28)
    return if !bitmap || !sheet || index.to_i < 0
    source_y = index.to_i * source_height.to_i
    return if sheet.respond_to?(:height) && source_y >= sheet.height.to_i
    source = Rect.new(0, source_y, source_width.to_i, source_height.to_i)
    target = Rect.new(x.to_i, y.to_i, width.to_i, height.to_i)
    bitmap.stretch_blt(target, sheet, source)
  rescue Exception
  end

  def self.move_value(move, key, default_value = "")
    return default_value if !move
    return move[key] if move.respond_to?(:has_key?) && move.has_key?(key)
    return move[key.to_sym] if move.respond_to?(:has_key?) && move.has_key?(key.to_sym)
    return default_value
  rescue Exception
    return default_value
  end

  def self.move_power_text(move)
    power = move_value(move, "power", 0).to_i
    return "-" if power <= 0
    return "???" if power == 1
    return power.to_s
  rescue Exception
    return "-"
  end

  def self.move_accuracy_text(move)
    accuracy = move_value(move, "accuracy", 0).to_i
    return "-" if accuracy <= 0
    return accuracy.to_s
  rescue Exception
    return "-"
  end

  def self.origin_text(entry)
    return _INTL("Equipo") if entry["loc"].to_s == "party"
    return _INTL("Caja {1} Slot {2}", entry["box"].to_i + 1, entry["slot"].to_i + 1)
  rescue Exception
    return ""
  end

  def self.dispose_icons(icons)
    return if !icons
    for sprite in icons
      begin
        sprite.dispose if sprite && !sprite.disposed?
      rescue Exception
      end
    end
    icons.clear if icons.respond_to?(:clear)
  rescue Exception
  end

  def self.pokemon_panel_rect
    return [4, 26, Graphics.width - 8, 94]
  rescue Exception
    return [4, 26, 504, 94]
  end

  def self.move_panel_rects
    y = 124
    height = 132
    left_width = (Graphics.width - 12) / 2
    right_x = 8 + left_width
    right_width = Graphics.width - right_x - 4
    return [[4, y, left_width, height], [right_x, y, right_width, height]]
  rescue Exception
    return [[4, 124, 250, 132], [258, 124, 250, 132]]
  end

  def self.detail_panel_y
    return 260
  rescue Exception
    return 260
  end

  def self.pokemon_card_metrics
    return [118, 30, 4]
  rescue Exception
    return [118, 30, 4]
  end

  def self.pokemon_visible_columns
    x, y, width, height = pokemon_panel_rect
    card_width, card_height, gap = pokemon_card_metrics
    columns = ((width - 12 + gap) / (card_width + gap)).to_i
    columns = 1 if columns < 1
    return columns
  rescue Exception
    return 4
  end

  def self.pokemon_max_scroll_column(results)
    columns = pokemon_visible_columns
    total_columns = ((results.length.to_i + 1) / 2).to_i
    max_scroll = total_columns - columns
    max_scroll = 0 if max_scroll < 0
    return max_scroll
  rescue Exception
    return 0
  end

  def self.adjust_pokemon_scroll(results, selected, scroll)
    columns = pokemon_visible_columns
    selected_column = selected.to_i / 2
    scroll = selected_column if selected_column < scroll.to_i
    scroll = selected_column - columns + 1 if selected_column >= scroll.to_i + columns
    scroll = 0 if scroll.to_i < 0
    max_scroll = pokemon_max_scroll_column(results || [])
    scroll = max_scroll if scroll.to_i > max_scroll
    return scroll
  rescue Exception
    return 0
  end

  def self.pokemon_card_position(index, scroll)
    x, y, width, height = pokemon_panel_rect
    card_width, card_height, gap = pokemon_card_metrics
    column = (index.to_i / 2) - scroll.to_i
    return nil if column < 0 || column >= pokemon_visible_columns
    row = index.to_i % 2
    card_x = x + 6 + column * (card_width + gap)
    card_y = y + 24 + row * 32
    return [card_x, card_y, card_width, card_height]
  rescue Exception
    return nil
  end

  def self.sync_pokemon_icons(viewport, icons, results, scroll)
    dispose_icons(icons)
    return if !defined?(PokemonIconSprite)
    columns = pokemon_visible_columns
    for column in 0...columns
      for row in 0...2
        index = (scroll.to_i + column) * 2 + row
        next if index < 0 || index >= results.length
        pos = pokemon_card_position(index, scroll)
        next if !pos
        pokemon = find_pokemon(results[index]) rescue nil
        next if !pokemon
        sprite = PokemonIconSprite.new(pokemon, viewport)
        sprite.zoom_x = 0.5 if sprite.respond_to?(:zoom_x=)
        sprite.zoom_y = 0.5 if sprite.respond_to?(:zoom_y=)
        sprite.x = pos[0] + 7
        sprite.y = pos[1] + 3
        sprite.z = 5
        icons.push(sprite)
      end
    end
  rescue Exception
  end

  def self.draw_pokemon_list(bitmap, results, selected, scroll, focus)
    x, y, width, height = pokemon_panel_rect
    draw_box(bitmap, x, y, width, height, Color.new(38, 72, 112), Color.new(16, 38, 70))
    old_size = bitmap.font.size rescue nil
    bitmap.font.size = 12 if bitmap.respond_to?(:font) && bitmap.font
    draw_text(bitmap, _INTL("Pokemon subidos"), x + width / 2, y + 5, 2, nil, width - 12, 18)
    columns = pokemon_visible_columns
    if results.length > columns * 2
      first = scroll.to_i * 2 + 1
      last = [((scroll.to_i + columns) * 2), results.length].min
      draw_text(bitmap, _INTL("{1}-{2}/{3}", first, last, results.length), x + width - 8, y + 5, 1, Color.new(232, 240, 248), 72, 18)
    end
    for column in 0...columns
      for row in 0...2
        index = (scroll.to_i + column) * 2 + row
        next if index < 0 || index >= results.length
        pos = pokemon_card_position(index, scroll)
        next if !pos
        card_x, row_y, card_width, card_height = pos
        entry = results[index]
        active = selected.to_i == index.to_i
        edge = active ? Color.new(255, 224, 72) : Color.new(40, 98, 58)
        fill = active ? Color.new(64, 178, 88) : Color.new(0, 142, 56)
        draw_box(bitmap, card_x, row_y, card_width, card_height, fill, edge)
        name = fit_text(bitmap, entry["name"].to_s, card_width - 64)
        draw_text(bitmap, name, card_x + 43, row_y + 2, 0, nil, card_width - 64, 16)
        level_text = _INTL("{1}>{2}", entry["oldLevel"].to_i, entry["newLevel"].to_i)
        draw_text(bitmap, level_text, card_x + 43, row_y + 16, 0, Color.new(232, 248, 232), 50, 14)
        count = (entry["learnedMoves"] || []).length rescue 0
        draw_text(bitmap, _INTL("+{1}", count), card_x + card_width - 8, row_y + 8, 1, Color.new(248, 248, 248), 28, 14)
      end
    end
    if focus.to_i == 0
      bitmap.fill_rect(x + 1, y + 1, width - 2, 2, Color.new(255, 224, 72))
      bitmap.fill_rect(x + 1, y + height - 3, width - 2, 2, Color.new(255, 224, 72))
    end
    bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
  rescue Exception
  end

  def self.learned_move_applied?(move)
    return true if move_value(move, "applied", false) == true
    return true if move_value(move, "learned", false) == true
    return true if move_value(move, "applied", false).to_s == "true"
    return false
  rescue Exception
    return false
  end

  def self.draw_move_row(bitmap, move, x, y, width, selected, learned, picked = false, applied = false)
    if applied
      edge = selected ? Color.new(255, 224, 72) : Color.new(58, 150, 72)
      fill = selected ? Color.new(218, 248, 184) : Color.new(188, 234, 176)
    elsif picked
      edge = Color.new(72, 168, 255)
      fill = Color.new(194, 228, 255)
    else
      edge = selected ? Color.new(255, 224, 72) : Color.new(214, 226, 236)
      fill = selected ? Color.new(255, 248, 176) : Color.new(238, 244, 248)
    end
    draw_box(bitmap, x, y, width, 20, fill, edge)
    id = move_value(move, "id", 0).to_i
    if id <= 0
      draw_text(bitmap, _INTL("Hueco vacio"), x + 8, y + 3, 0, Color.new(48, 52, 60), width - 16, 16)
      return
    end
    type = move_value(move, "type", -1).to_i
    category = move_value(move, "category", -1).to_i
    draw_sheet_icon(bitmap, type_bitmap, type, x + 3, y + 3, 15, 17, 24, 28)
    draw_sheet_icon(bitmap, category_bitmap, category, x + 22, y + 5, 26, 11, 64, 28)
    stat_width = learned ? 116 : 88
    name_width = width - stat_width - 58
    name = fit_text(bitmap, move_value(move, "name", "").to_s, name_width)
    draw_text(bitmap, name, x + 55, y + 3, 0, Color.new(36, 40, 48), name_width, 16)
    stat = learned ? _INTL("N{1} | P{2} Pr{3} PP{4}", move_value(move, "level", 0).to_i, move_power_text(move), move_accuracy_text(move), move_value(move, "pp", 0).to_i) :
                     _INTL("P{1} Pr{2} PP{3}", move_power_text(move), move_accuracy_text(move), move_value(move, "pp", 0).to_i)
    old_size = bitmap.font.size rescue nil
    bitmap.font.size = 11 if bitmap.respond_to?(:font) && bitmap.font
    draw_text(bitmap, stat, x + width - 4, y + 3, 1, Color.new(36, 40, 48), stat_width, 16)
    bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
  rescue Exception
  end

  def self.move_visible_count(height)
    count = (height.to_i - 22) / 22
    count = 1 if count < 1
    return count
  rescue Exception
    return 4
  end

  def self.adjust_scroll(selected, scroll, visible)
    scroll = selected.to_i if selected.to_i < scroll.to_i
    scroll = selected.to_i - visible.to_i + 1 if selected.to_i >= scroll.to_i + visible.to_i
    scroll = 0 if scroll.to_i < 0
    return scroll
  rescue Exception
    return 0
  end

  def self.draw_move_panel(bitmap, title, moves, selected, scroll, x, y, width, height, focus_active, learned, picked_index = nil)
    draw_box(bitmap, x, y, width, height, Color.new(236, 244, 250), Color.new(40, 80, 112))
    old_size = bitmap.font.size rescue nil
    bitmap.font.size = 12 if bitmap.respond_to?(:font) && bitmap.font
    draw_text(bitmap, title, x + width / 2, y + 4, 2, Color.new(40, 44, 52), width - 16, 18)
    visible = move_visible_count(height)
    for row in 0...visible
      index = scroll.to_i + row
      move = moves[index] rescue nil
      picked = picked_index != nil && picked_index.to_i == index.to_i
      applied = learned && learned_move_applied?(move)
      draw_move_row(bitmap, move, x + 6, y + 22 + row * 22, width - 12, selected.to_i == index && focus_active, learned, picked, applied)
    end
    if moves && moves.length > visible
      draw_text(bitmap, _INTL("{1}/{2}", selected.to_i + 1, moves.length), x + width - 8, y + 4, 1, Color.new(40, 44, 52), 44, 16)
    end
    if focus_active
      bitmap.fill_rect(x + 1, y + 1, width - 2, 2, Color.new(255, 224, 72))
      bitmap.fill_rect(x + 1, y + height - 3, width - 2, 2, Color.new(255, 224, 72))
    end
    bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
  rescue Exception
  end

  def self.selected_detail_move(entry, focus, learned_index, current_index)
    if focus.to_i == 2
      return (entry["currentMoves"] || [])[current_index.to_i] rescue nil
    end
    return (entry["learnedMoves"] || [])[learned_index.to_i] rescue nil
  rescue Exception
    return nil
  end

  def self.draw_compared_move_detail(bitmap, title, move, x, y, width, height, base = nil)
    base = Color.new(248, 248, 248) if !base
    old_size = bitmap.font.size rescue nil
    bitmap.font.size = 12 if bitmap.respond_to?(:font) && bitmap.font
    draw_text(bitmap, title, x, y, 0, base, width, 16)
    if !move || move_value(move, "id", 0).to_i <= 0
      draw_text(bitmap, _INTL("Hueco vacio"), x, y + 18, 0, Color.new(232, 240, 248), width, 16)
      bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
      return
    end
    name = fit_text(bitmap, move_value(move, "name", "").to_s, width - 56)
    draw_text(bitmap, name, x, y + 18, 0, nil, width - 56, 16)
    draw_sheet_icon(bitmap, type_bitmap, move_value(move, "type", -1).to_i, x + width - 50, y + 20, 16, 18, 24, 28)
    draw_sheet_icon(bitmap, category_bitmap, move_value(move, "category", -1).to_i, x + width - 28, y + 22, 28, 12, 64, 28)
    bitmap.font.size = 12 if bitmap.respond_to?(:font) && bitmap.font
    stat = _INTL("Pot {1}  Prec {2}  PP {3}", move_power_text(move), move_accuracy_text(move), move_value(move, "pp", 0).to_i)
    draw_text(bitmap, fit_text(bitmap, stat, width), x, y + 36, 0, Color.new(232, 240, 248), width, 16)
    desc = move_value(move, "description", "").to_s
    lines = wrap_lines(bitmap, desc, width, ((height.to_i - 54) / 16))
    for i in 0...lines.length
      draw_text(bitmap, lines[i], x, y + 54 + i * 16, 0, Color.new(232, 240, 248), width, 16)
    end
    bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
  rescue Exception
  end

  def self.draw_detail_panel(bitmap, entry, focus, learned_index, current_index, chosen_learned_index, status)
    x = 4
    y = detail_panel_y
    width = Graphics.width - 8
    height = Graphics.height - y - 4
    draw_box(bitmap, x, y, width, height, Color.new(68, 84, 104), Color.new(42, 54, 70))
    learned = entry["learnedMoves"] || []
    current = entry["currentMoves"] || []
    chosen = chosen_learned_index != nil ? learned[chosen_learned_index.to_i] : nil
    preview_new = learned[learned_index.to_i] rescue nil
    preview_current = current[current_index.to_i] rescue nil
    old_size = bitmap.font.size rescue nil
    bitmap.font.size = 12 if bitmap.respond_to?(:font) && bitmap.font
    if focus.to_i == 0
      pokemon = find_pokemon(entry) rescue nil
      title = pokemon ? _INTL("{1} Nv.{2}", pokemon.name, pokemon.level) : entry["name"].to_s
      draw_text(bitmap, fit_text(bitmap, title, 178), x + 12, y + 8, 0, nil, 186, 18)
      draw_text(bitmap, fit_text(bitmap, origin_text(entry), 128), x + 216, y + 8, 0, Color.new(232, 240, 248), 136, 18)
      count = (entry["learnedMoves"] || []).length rescue 0
      draw_text(bitmap, _INTL("{1} nuevos. C/Enter: detalles Pokemon.", count), x + 12, y + 28, 0, Color.new(232, 240, 248), width - 24, 18)
    else
      half = (width - 30) / 2
      bitmap.fill_rect(x + 14 + half, y + 8, 2, height - 32, Color.new(42, 54, 70))
      new_color = chosen && chosen.equal?(preview_new) ? Color.new(184, 224, 255) : Color.new(248, 248, 248)
      draw_compared_move_detail(bitmap, _INTL("Movimiento nuevo"), preview_new, x + 12, y + 8, half, height - 30, new_color)
      draw_compared_move_detail(bitmap, _INTL("Movimiento actual"), preview_current, x + 18 + half, y + 8, half, height - 30)
    end
    bitmap.font.size = 10 if bitmap.respond_to?(:font) && bitmap.font
    footer = status.to_s == "" ? _INTL("Izq/der: panel  Arr/abajo: mover  C/Enter: usar/detalles  X: info  B: salir") : status.to_s
    draw_text(bitmap, fit_text(bitmap, footer, width - 24), x + 12, y + height - 22, 0, Color.new(248, 248, 248), width - 24, 16)
    bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
  rescue Exception
  end

  def self.clamp_review_indexes(results, selected, learned_index, current_index)
    selected = 0 if selected.to_i < 0
    selected = results.length - 1 if selected.to_i >= results.length
    entry = results[selected] || {}
    learned = entry["learnedMoves"] || []
    current = entry["currentMoves"] || []
    learned_index = 0 if learned_index.to_i < 0
    learned_index = learned.length - 1 if learned.length > 0 && learned_index.to_i >= learned.length
    learned_index = 0 if learned.length <= 0
    current_index = 0 if current_index.to_i < 0
    current_index = current.length - 1 if current.length > 0 && current_index.to_i >= current.length
    current_index = 0 if current.length <= 0
    return [selected, learned_index, current_index]
  rescue Exception
    return [0, 0, 0]
  end

  def self.move_pokemon_selection(results, selected, direction)
    count = results ? results.length.to_i : 0
    return selected.to_i if count <= 0
    columns = ((count + 1) / 2).to_i
    column = selected.to_i / 2
    row = selected.to_i % 2
    if direction == :left
      column = (column - 1) % columns
    elsif direction == :right
      column = (column + 1) % columns
    elsif direction == :up
      row = 0 if row == 1
    elsif direction == :down
      row = 1 if row == 0
    end
    target = column * 2 + row
    target = column * 2 if target >= count
    target = count - 1 if target >= count
    target = 0 if target < 0
    return target
  rescue Exception
    return selected.to_i
  end

  def self.teach_selected_move(entry, learned_index, current_index)
    learned = entry["learnedMoves"] || []
    current = entry["currentMoves"] || []
    move = learned[learned_index.to_i] rescue nil
    return [false, _INTL("Selecciona un movimiento nuevo.")] if !move || move_value(move, "id", 0).to_i <= 0
    replace = current[current_index.to_i] rescue nil
    args = {
      "loc" => entry["loc"].to_s,
      "index" => entry["index"].to_i.to_s,
      "box" => entry["box"].to_i.to_s,
      "slot" => entry["slot"].to_i.to_s,
      "move" => move_value(move, "id", 0).to_i.to_s,
      "replaceSlot" => (replace ? move_value(replace, "slot", -1).to_i : -1).to_s
    }
    return learn_move(args)
  rescue Exception
    return [false, _INTL("No se pudo aprender ese movimiento.")]
  end

  def self.move_display_name(move, empty_text = nil)
    empty_text = _INTL("Hueco vacio") if !empty_text
    return empty_text if !move || move_value(move, "id", 0).to_i <= 0
    name = move_value(move, "name", "").to_s
    return name == "" ? empty_text : name
  rescue Exception
    return empty_text || ""
  end

  def self.confirm_teach_move(entry, learned_index, current_index)
    learned = entry["learnedMoves"] || []
    current = entry["currentMoves"] || []
    learned_move = learned[learned_index.to_i] rescue nil
    current_move = current[current_index.to_i] rescue nil
    return false if !learned_move || move_value(learned_move, "id", 0).to_i <= 0
    learned_name = move_display_name(learned_move)
    if current_move && move_value(current_move, "id", 0).to_i > 0
      current_name = move_display_name(current_move)
      return Kernel.pbConfirmMessage(_INTL("Seguro que quieres aprender {1} por {2}?", learned_name, current_name))
    end
    return Kernel.pbConfirmMessage(_INTL("Seguro que quieres aprender {1} en un hueco vacio?", learned_name))
  rescue Exception
    return false
  end

  def self.full_move_detail_text(move)
    return _INTL("Selecciona un movimiento.") if !move || move_value(move, "id", 0).to_i <= 0
    return _INTL("Movimiento: {1}\nTipo: {2}\nClase: {3}\nPotencia: {4}  Precision: {5}  PP: {6}\n\n{7}",
      move_value(move, "name", "").to_s,
      move_value(move, "typeName", "").to_s,
      move_value(move, "categoryName", "").to_s,
      move_power_text(move),
      move_accuracy_text(move),
      move_value(move, "pp", 0).to_i,
      move_value(move, "description", "").to_s)
  rescue Exception
    return _INTL("No se pudo mostrar ese movimiento.")
  end

  def self.show_pokemon_details(entry)
    pokemon = find_pokemon(entry) rescue nil
    return false if !pokemon
    if defined?(SebiPvpPreview) && SebiPvpPreview.respond_to?(:show_single_pokemon_details)
      SebiPvpPreview.show_single_pokemon_details(_INTL("Detalles de {1}", pokemon.name), pokemon)
      return true
    elsif defined?(SebiPvpPreview) && SebiPvpPreview.respond_to?(:show_readonly_team)
      SebiPvpPreview.show_readonly_team(_INTL("Detalles de {1}", pokemon.name), [pokemon])
      return true
    end
    Kernel.pbMessage(_INTL("{1} Nv.{2}", pokemon.name, pokemon.level))
    return true
  rescue Exception
    return false
  end

  def self.detail_trigger?
    if defined?(SebiControls) && SebiControls.respond_to?(:button_x_trigger?)
      return true if SebiControls.button_x_trigger?
    end
    return Input.trigger?(Input::X)
  rescue Exception
    return false
  end

  def self.set_internal_visible(overlay, icons, value)
    begin
      overlay.visible = value if overlay && overlay.respond_to?(:visible=)
    rescue Exception
    end
    begin
      for icon in icons
        icon.visible = value if icon && icon.respond_to?(:visible=)
      end
    rescue Exception
    end
  end

  def self.draw_internal_review(bitmap, results, selected, scroll, focus, learned_index, learned_scroll, current_index, current_scroll, chosen_learned_index, status)
    bitmap.clear
    begin
      @review_bg_bitmap = AnimatedBitmap.new("Graphics/Pictures/partybg") if !@review_bg_bitmap
      bg = @review_bg_bitmap.bitmap
      bitmap.stretch_blt(Rect.new(0, 0, Graphics.width, Graphics.height), bg, Rect.new(0, 0, bg.width, bg.height)) if bg
    rescue Exception
      bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(30, 58, 94))
    end
    apply_font(bitmap)
    old_size = bitmap.font.size rescue nil
    bitmap.font.size = 14 if bitmap.respond_to?(:font) && bitmap.font
    draw_text(bitmap, _INTL("Revision Rapidin"), Graphics.width / 2, 4, 2, nil, Graphics.width - 16, 20)
    selected, learned_index, current_index = clamp_review_indexes(results, selected, learned_index, current_index)
    entry = results[selected] || {}
    draw_pokemon_list(bitmap, results, selected, scroll, focus)
    rects = move_panel_rects
    left = rects[0]
    right = rects[1]
    draw_move_panel(bitmap, _INTL("Movimientos nuevos"), entry["learnedMoves"] || [], learned_index, learned_scroll, left[0], left[1], left[2], left[3], focus.to_i == 1, true, chosen_learned_index)
    draw_move_panel(bitmap, _INTL("Movimientos actuales"), entry["currentMoves"] || [], current_index, current_scroll, right[0], right[1], right[2], right[3], focus.to_i == 2, false)
    draw_detail_panel(bitmap, entry, focus, learned_index, current_index, chosen_learned_index, status)
    bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
  rescue Exception
  end

  def self.accept_trigger?
    if defined?(SebiControls) && SebiControls.respond_to?(:accept_trigger?)
      return true if SebiControls.accept_trigger?
    end
    return Input.trigger?(Input::C)
  rescue Exception
    return false
  end

  def self.back_trigger?
    if defined?(SebiControls) && SebiControls.respond_to?(:back_trigger?)
      return true if SebiControls.back_trigger?
    end
    return Input.trigger?(Input::B)
  rescue Exception
    return false
  end

  def self.show_internal(results)
    return false if !results || results.length == 0
    viewport = nil
    overlay = nil
    icons = []
    viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    viewport.z = 100100
    overlay = BitmapSprite.new(Graphics.width, Graphics.height, viewport)
    overlay.z = 1
    selected = 0
    scroll = 0
    focus = 0
    learned_index = 0
    learned_scroll = 0
    current_index = 0
    current_scroll = 0
    chosen_learned_index = nil
    status = ""
    redraw = true
    loop do
      if redraw
        selected, learned_index, current_index = clamp_review_indexes(results, selected, learned_index, current_index)
        scroll = adjust_pokemon_scroll(results, selected, scroll)
        rects = move_panel_rects
        learned_scroll = adjust_scroll(learned_index, learned_scroll, move_visible_count(rects[0][3]))
        current_scroll = adjust_scroll(current_index, current_scroll, move_visible_count(rects[1][3]))
        learned_count = ((results[selected] || {})["learnedMoves"] || []).length
        chosen_learned_index = nil if chosen_learned_index != nil && (chosen_learned_index.to_i < 0 || chosen_learned_index.to_i >= learned_count)
        draw_internal_review(overlay.bitmap, results, selected, scroll, focus, learned_index, learned_scroll, current_index, current_scroll, chosen_learned_index, status)
        sync_pokemon_icons(viewport, icons, results, scroll)
        redraw = false
      end
      Graphics.update
      Input.update
      SebiVisualMultiplayer.global_tick if defined?(SebiVisualMultiplayer)
      if Input.trigger?(Input::LEFT)
        if focus == 0
          selected = move_pokemon_selection(results, selected, :left)
          learned_index = 0
          learned_scroll = 0
          current_index = 0
          current_scroll = 0
          chosen_learned_index = nil
        elsif focus == 2
          focus = 1
        end
        status = ""
        redraw = true
      elsif Input.trigger?(Input::RIGHT)
        if focus == 0
          selected = move_pokemon_selection(results, selected, :right)
          learned_index = 0
          learned_scroll = 0
          current_index = 0
          current_scroll = 0
          chosen_learned_index = nil
        elsif focus == 1
          focus = 2
        end
        status = ""
        redraw = true
      elsif Input.trigger?(Input::UP)
        if focus == 0
          new_selected = move_pokemon_selection(results, selected, :up)
          if new_selected != selected
            selected = new_selected
            learned_index = 0
            learned_scroll = 0
            current_index = 0
            current_scroll = 0
            chosen_learned_index = nil
          end
        elsif focus == 1
          count = ((results[selected] || {})["learnedMoves"] || []).length
          if learned_index.to_i <= 0
            focus = 0
          else
            learned_index -= 1 if count > 0
          end
        else
          count = ((results[selected] || {})["currentMoves"] || []).length
          if current_index.to_i <= 0
            focus = 0
          else
            current_index -= 1 if count > 0
          end
        end
        status = ""
        redraw = true
      elsif Input.trigger?(Input::DOWN)
        if focus == 0
          if (selected.to_i % 2) == 1 || selected.to_i + 1 >= results.length
            focus = 1
          else
            selected = move_pokemon_selection(results, selected, :down)
            learned_index = 0
            learned_scroll = 0
            current_index = 0
            current_scroll = 0
            chosen_learned_index = nil
          end
        elsif focus == 1
          count = ((results[selected] || {})["learnedMoves"] || []).length
          learned_index = (learned_index + 1) % count if count > 0
        else
          count = ((results[selected] || {})["currentMoves"] || []).length
          current_index = (current_index + 1) % count if count > 0
        end
        status = ""
        redraw = true
      elsif accept_trigger?
        if focus == 0
          set_internal_visible(overlay, icons, false)
          ok = show_pokemon_details(results[selected] || {})
          set_internal_visible(overlay, icons, true)
          status = ok ? "" : _INTL("No se pudieron abrir los detalles del Pokemon.")
        elsif focus == 1
          move = ((results[selected] || {})["learnedMoves"] || [])[learned_index.to_i] rescue nil
          if move && move_value(move, "id", 0).to_i > 0
            chosen_learned_index = learned_index
            focus = 2
            status = _INTL("Ahora elige el movimiento actual que quieres reemplazar.")
            pbPlayDecisionSE() if defined?(pbPlayDecisionSE)
          else
            status = _INTL("Selecciona un movimiento nuevo valido.")
            pbPlayBuzzerSE() if defined?(pbPlayBuzzerSE)
          end
        else
          if chosen_learned_index == nil
            status = _INTL("Selecciona primero un movimiento nuevo.")
            pbPlayBuzzerSE() if defined?(pbPlayBuzzerSE)
          else
            set_internal_visible(overlay, icons, false)
            confirmed = confirm_teach_move(results[selected] || {}, chosen_learned_index, current_index)
            set_internal_visible(overlay, icons, true)
            if confirmed
              ok, msg = teach_selected_move(results[selected] || {}, chosen_learned_index, current_index)
              status = msg.to_s
              if ok
                chosen_learned_index = nil
                pbPlayDecisionSE() if defined?(pbPlayDecisionSE)
              else
                pbPlayBuzzerSE() if defined?(pbPlayBuzzerSE)
              end
            else
              status = _INTL("Aprendizaje cancelado.")
              pbPlayBuzzerSE() if defined?(pbPlayBuzzerSE)
            end
          end
        end
        redraw = true
      elsif detail_trigger?
        set_internal_visible(overlay, icons, false)
        if focus == 0
          show_pokemon_details(results[selected] || {})
        else
          move = selected_detail_move(results[selected] || {}, focus, learned_index, current_index)
          Kernel.pbMessage(full_move_detail_text(move))
        end
        set_internal_visible(overlay, icons, true)
        redraw = true
      elsif back_trigger?
        set_internal_visible(overlay, icons, false)
        leave = Kernel.pbConfirmMessage(_INTL("Seguro que quieres salir del modo Rapidin?"))
        set_internal_visible(overlay, icons, true)
        if leave
          break
        else
          status = _INTL("Salida cancelada.")
          redraw = true
        end
      end
    end
    return true
  rescue Exception
    return false
  ensure
    dispose_icons(icons)
    begin
      overlay.bitmap.dispose if overlay && overlay.bitmap && !overlay.bitmap.disposed?
      overlay.dispose if overlay && !overlay.disposed?
      viewport.dispose if viewport && !viewport.disposed?
    rescue Exception
    end
  end

  def self.open(results)
    @results = results || []
    write_state
    return show_internal(@results)
  rescue Exception
    return false
  end

  def self.percent_decode(value)
    return SebiSaveEditor.percent_decode(value) if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:percent_decode)
    value = value.to_s.gsub("+", " ")
    return value.gsub(/%([0-9A-Fa-f]{2})/) { $1.to_i(16).chr }
  rescue Exception
    return value.to_s
  end

  def self.parse_command(line)
    return SebiSaveEditor.parse_command(line) if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:parse_command)
    parts = line.to_s.gsub(/\r|\n/, "").split("|")
    ret = { "seq" => parts[0].to_s, "cmd" => parts[1].to_s, "args" => {} }
    for i in 2...parts.length
      pair = parts[i].split("=", 2)
      next if pair.length < 2
      ret["args"][pair[0].to_s] = percent_decode(pair[1].to_s)
    end
    return ret
  rescue Exception
    return nil
  end

  def self.find_pokemon(args)
    loc = args["loc"].to_s
    if loc == "party"
      index = args["index"].to_i
      return nil if !$Trainer || !$Trainer.party || index < 0 || index >= $Trainer.party.length
      return $Trainer.party[index]
    elsif loc == "box"
      box_index = args["box"].to_i
      slot = args["slot"].to_i
      return nil if !$PokemonStorage || !$PokemonStorage.respond_to?(:boxes)
      return nil if box_index < 0 || box_index >= $PokemonStorage.boxes.length
      box = $PokemonStorage.boxes[box_index]
      return nil if !box || slot < 0 || slot >= box.length
      return box[slot]
    end
    return nil
  rescue Exception
    return nil
  end

  def self.refresh_entry(args, pokemon)
    return if !@results || !pokemon
    @results.each do |entry|
      next if entry["loc"].to_s != args["loc"].to_s
      next if entry["index"].to_i != args["index"].to_i
      next if entry["box"].to_i != args["box"].to_i
      next if entry["slot"].to_i != args["slot"].to_i
      entry["currentMoves"] = SebiCheats.current_move_details(pokemon) if defined?(SebiCheats)
    end
  rescue Exception
  end

  def self.mark_applied_move(args, move_id)
    return if !@results || move_id.to_i <= 0
    @results.each do |entry|
      next if entry["loc"].to_s != args["loc"].to_s
      next if entry["index"].to_i != args["index"].to_i
      next if entry["box"].to_i != args["box"].to_i
      next if entry["slot"].to_i != args["slot"].to_i
      applied = entry["appliedMoveIds"] || []
      applied.push(move_id.to_i) if !applied.include?(move_id.to_i)
      entry["appliedMoveIds"] = applied
      for move in (entry["learnedMoves"] || [])
        next if move_value(move, "id", 0).to_i != move_id.to_i
        move["applied"] = true if move.respond_to?(:[]=)
        move["learned"] = true if move.respond_to?(:[]=)
      end
    end
  rescue Exception
  end

  def self.learn_move(args)
    pokemon = find_pokemon(args)
    return [false, _INTL("No se encontro ese Pokemon.")] if !pokemon
    move_id = args["move"].to_i
    slot = args["replaceSlot"].to_i
    return [false, _INTL("Movimiento no valido.")] if move_id <= 0
    begin
      return [false, _INTL("{1} ya conoce ese movimiento.", pokemon.name)] if pokemon.hasMove?(move_id)
    rescue Exception
    end
    empty = -1
    for i in 0...4
      begin
        if !pokemon.moves[i] || pokemon.moves[i].id.to_i <= 0
          empty = i
          break
        end
      rescue Exception
      end
    end
    slot = empty if slot < 0 || slot > 3
    return [false, _INTL("Elige un movimiento actual para reemplazar.")] if slot < 0 || slot > 3
    pokemon.moves[slot] = PBMove.new(move_id) if defined?(PBMove)
    pokemon.calcStats if pokemon.respond_to?(:calcStats)
    refresh_entry(args, pokemon)
    mark_applied_move(args, move_id)
    write_state
    return [true, _INTL("{1} aprendio {2}.", pokemon.name, (PBMoves.getName(move_id).to_s rescue ""))]
  rescue Exception
    return [false, _INTL("No se pudo aprender ese movimiento.")]
  end

  def self.write_result(seq, ok, message)
    ensure_runtime
    atomic_write(result_path, json({
      "seq" => seq.to_s,
      "ok" => ok ? true : false,
      "message" => message.to_s,
      "time" => Time.now.to_s
    }))
  rescue Exception
  end

  def self.process_commands
    path = command_path
    return if !FileTest.exist?(path)
    text = ""
    File.open(path, "rb") { |file| text = file.read }
    return if !text || text == ""
    File.open(path, "wb") { |file| file.write("") }
    text.each_line do |line|
      command = parse_command(line)
      next if !command || command["cmd"].to_s == ""
      ok = false
      msg = ""
      case command["cmd"].to_s
      when "learn_move"
        ok, msg = learn_move(command["args"] || {})
      else
        ok = false
        msg = _INTL("Comando desconocido.")
      end
      write_result(command["seq"], ok, msg)
    end
  rescue Exception
    write_result("error", false, _INTL("Error leyendo comandos de movimientos."))
  end

  def self.update
    return if @processing_command
    frame = Graphics.frame_count rescue 0
    return if @last_command_poll_frame && frame - @last_command_poll_frame < COMMAND_POLL_FRAMES
    @last_command_poll_frame = frame
    @processing_command = true
    process_commands
    @processing_command = false
  rescue SystemExit
    raise
  rescue Exception
    @processing_command = false
  end
end

module SebiPokemonDB
  BASE_URL = "https://pokemondb.net/pokedex"
  @last_open_frame = 0
  @pending_next_pokemon = nil
  @pending_next_name = nil
  @pending_next_prompt = false
  @pending_next_switch = false
  @pending_next_expire_frame = nil

  def self.original_species_name(pokemon)
    return "" if !pokemon
    return PBSpecies.getName(pokemon.species).to_s if defined?(PBSpecies)
    return pokemon.name.to_s
  rescue Exception
    return pokemon ? pokemon.name.to_s : ""
  end

  def self.slug_for_name(name)
    slug = name.to_s.downcase
    replacements = {
      "♀" => "-f", "♂" => "-m", "." => "", "'" => "", ":" => "",
      " " => "-", "_" => "-", "é" => "e", "è" => "e", "á" => "a",
      "à" => "a", "í" => "i", "ó" => "o", "ú" => "u", "ñ" => "n"
    }
    replacements.each { |from, to| slug = slug.gsub(from, to) }
    slug = slug.gsub(/[^a-z0-9\-]/, "")
    slug = slug.gsub(/\-+/, "-")
    slug = slug.gsub(/^\-|\-$/, "")
    return slug
  rescue Exception
    return name.to_s.downcase
  end

  def self.url_for_name(name)
    slug = slug_for_name(name)
    return BASE_URL if slug == ""
    return BASE_URL + "/" + slug
  end

  def self.url_for_pokemon(pokemon)
    return url_for_name(original_species_name(pokemon))
  end

  def self.name_for_species(species)
    species = species.to_i
    return "" if species <= 0
    return PBSpecies.getName(species).to_s if defined?(PBSpecies)
    return species.to_s
  rescue Exception
    return species.to_s
  end

  def self.url_for_species(species)
    return url_for_name(name_for_species(species))
  end

  def self.open_url(url)
    url = url.to_s
    if defined?(Win32API)
      shell = Win32API.new("shell32", "ShellExecuteA", "LPPPPI", "I")
      result = shell.call(0, "open", url, nil, nil, 1)
      return if result && result.to_i > 32
    end
    system("cmd /c start \"\" \"" + url.gsub("\"", "") + "\"")
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir el navegador."))
  end

  def self.open_pokemon(pokemon)
    return if !pokemon
    open_url(url_for_pokemon(pokemon))
  end

  def self.open_species(species)
    name = name_for_species(species)
    return false if !name || name.to_s.strip == ""
    open_name(name)
    return true
  rescue Exception
    return false
  end

  def self.open_name(name)
    return if !name || name.to_s.strip == ""
    open_url(url_for_name(name))
  end

  def self.open_team(party)
    return if !party || party.length == 0
    names = []
    for pokemon in party
      next if !pokemon || pokemon.isEgg?
      names.push(original_species_name(pokemon))
    end
    if names.length == 0
      Kernel.pbMessage(_INTL("No hay Pokemon validos para abrir en la DB."))
      return
    end
    return if !Kernel.pbConfirmMessage(_INTL("Abrir en PokemonDB los datos de {1} Pokemon del equipo?", names.length))
    for pokemon in party
      next if !pokemon || pokemon.isEgg?
      open_pokemon(pokemon)
    end
  end

  def self.open_first_opponent(battle)
    return if !battle || !battle.battlers
    pokemon = nil
    for i in [1, 3]
      battler = battle.battlers[i] rescue nil
      next if !battler || battler.isFainted?
      pokemon = battler.pokemon rescue nil
      break if pokemon
    end
    if !pokemon
      Kernel.pbMessage(_INTL("No hay Pokemon rival para abrir en la DB."))
      return
    end
    open_pokemon(pokemon)
  end

  def self.opposing_battler_indexes(battle)
    ret = []
    begin
      if battle && battle.respond_to?(:pbIsOpposing?) && battle.battlers
        for i in 0...battle.battlers.length
          ret.push(i) if battle.pbIsOpposing?(i)
        end
      end
    rescue Exception
      ret = []
    end
    ret = [1, 3] if ret.length == 0
    return ret
  end

  def self.open_visible_opponents(battle)
    return false if !battle || !battle.battlers
    opened = 0
    for i in opposing_battler_indexes(battle)
      battler = battle.battlers[i] rescue nil
      next if !battler || battler.isFainted?
      pokemon = battler.pokemon rescue nil
      next if !pokemon || (pokemon.isEgg? rescue false)
      open_pokemon(pokemon)
      opened += 1
    end
    if opened <= 0
      Kernel.pbMessage(_INTL("No hay Pokemon rival para abrir en la DB."))
      return false
    end
    return true
  rescue Exception
    return false
  end

  def self.lookup_key(name)
    return slug_for_name(name.to_s)
  rescue Exception
    return name.to_s.downcase
  end

  def self.find_party_pokemon_by_name(battle, name)
    key = lookup_key(name)
    return nil if !battle || key == ""
    for side_index in [1, 3]
      party = nil
      begin
        party = battle.pbParty(side_index)
      rescue Exception
        party = nil
      end
      next if !party
      for pokemon in party
        next if !pokemon
        begin
          next if pokemon.isEgg?
        rescue Exception
        end
        begin
          next if pokemon.respond_to?(:hp) && pokemon.hp.to_i <= 0
        rescue Exception
        end
        return pokemon if lookup_key(pokemon.name) == key
        return pokemon if lookup_key(original_species_name(pokemon)) == key
      end
    end
    return nil
  rescue Exception
    return nil
  end

  def self.extract_next_name_from_message(message)
    text = message.to_s.gsub(/\r|\n/, " ")
    match = text.match(/va a enviar a\s+(.+?)(?:\.|!|\?|$)/i)
    return nil if !match
    name = match[1].to_s.strip
    return nil if name == ""
    return name
  rescue Exception
    return nil
  end

  def self.capture_pending_next_from_message(battle, message)
    name = extract_next_name_from_message(message)
    return false if !name
    @pending_next_name = name
    @pending_next_pokemon = find_party_pokemon_by_name(battle, name)
    @pending_next_prompt = false
    @pending_next_switch = false
    @pending_next_expire_frame = nil
    return true
  rescue Exception
    return false
  end

  def self.shift_confirm_message?(message)
    text = message.to_s.downcase
    return text.include?("quieres cambiar")
  rescue Exception
    return false
  end

  def self.begin_pending_next_prompt
    @pending_next_prompt = true if @pending_next_pokemon || (@pending_next_name && @pending_next_name != "")
  rescue Exception
  end

  def self.begin_pending_next_switch
    if @pending_next_pokemon || (@pending_next_name && @pending_next_name != "")
      @pending_next_prompt = false
      @pending_next_switch = true
      @pending_next_expire_frame = (Graphics.frame_count rescue 0) + 1200
    end
  rescue Exception
  end

  def self.pending_next_expired?
    return false if !@pending_next_expire_frame
    frame = Graphics.frame_count rescue 0
    if frame > @pending_next_expire_frame
      clear_pending_next
      return true
    end
    return false
  rescue Exception
    return false
  end

  def self.pending_next_active?
    pending_next_expired?
    return @pending_next_prompt || @pending_next_switch
  rescue Exception
    return false
  end

  def self.pending_next_switch?
    pending_next_expired?
    return @pending_next_switch ? true : false
  rescue Exception
    return false
  end

  def self.pending_next_pokemon_for_switch
    pending_next_expired?
    return nil if !@pending_next_switch
    return @pending_next_pokemon
  rescue Exception
    return nil
  end

  def self.clear_pending_next
    @pending_next_pokemon = nil
    @pending_next_name = nil
    @pending_next_prompt = false
    @pending_next_switch = false
    @pending_next_expire_frame = nil
  rescue Exception
  end

  def self.open_pending_next
    return false if !pending_next_active?
    if @pending_next_pokemon
      open_pokemon(@pending_next_pokemon)
      return true
    elsif @pending_next_name && @pending_next_name != ""
      open_name(@pending_next_name)
      return true
    end
    return false
  rescue Exception
    return false
  end

  def self.open_pending_or_first_opponent(battle)
    return true if open_pending_next
    return open_visible_opponents(battle)
  rescue Exception
    return false
  end

  def self.can_open_hotkey?
    return false if Graphics.frame_count - @last_open_frame < 30
    @last_open_frame = Graphics.frame_count
    return true
  rescue Exception
    return true
  end

  def self.db_hotkey_trigger?
    if defined?(SebiExtraControls)
      return SebiExtraControls.db_trigger?
    elsif defined?(SebiControls)
      return SebiControls.db_trigger?
    elsif defined?(Input)
      return Input.trigger?(Input::F3)
    end
    return false
  rescue Exception
    return false
  end

  def self.open_hotkey_for_pokemon(pokemon)
    return false if !pokemon
    return false if (pokemon.isEgg? rescue false)
    return false if !db_hotkey_trigger?
    return false if !can_open_hotkey?
    open_pokemon(pokemon)
    return true
  rescue Exception
    return false
  end

  def self.open_hotkey_for_species(species)
    return false if species.to_i <= 0
    return false if !db_hotkey_trigger?
    return false if !can_open_hotkey?
    return open_species(species)
  rescue Exception
    return false
  end
end

module SebiSaveEditor
  EDITOR_KEY = 0x76
  COOLDOWN_FRAMES = 20
  SNAPSHOT_FRAMES = 60
  @last_open_frame = 0
  @last_snapshot_frame = -9999
  @active = false
  @data_written = false
  @external_edit_path = ""
  @external_edit_sections = nil
  @window_started_frame = -9999

  def self.editor_path
    return File.expand_path("multiplayer/save-editor/SebiSaveEditor.ps1")
  rescue Exception
    return "multiplayer/save-editor/SebiSaveEditor.ps1"
  end

  def self.base_dir
    return File.expand_path("multiplayer/save-editor")
  rescue Exception
    return "multiplayer/save-editor"
  end

  def self.runtime_dir
    return SebiLinkPaths.runtime_dir("save-editor") if defined?(SebiLinkPaths)
    return File.expand_path("multiplayer/save-editor/runtime")
  rescue Exception
    return "SebiLinkConfig/save-editor/runtime"
  end

  def self.state_path
    return File.join(runtime_dir, "state.json")
  end

  def self.data_path
    return File.join(runtime_dir, "data.json")
  end

  def self.command_path
    return File.join(runtime_dir, "commands.txt")
  end

  def self.result_path
    return File.join(runtime_dir, "last_result.json")
  end

  def self.alive_path
    return File.join(runtime_dir, "window_alive.txt")
  end

  def self.current_summary_scene=(scene)
    @current_summary_scene = scene
  rescue Exception
  end

  def self.current_summary_scene
    return @current_summary_scene
  rescue Exception
    return nil
  end

  def self.open_after_load_path
    return File.join(runtime_dir, "open_after_load.txt")
  end

  def self.edit_target_path
    return File.join(runtime_dir, "edit_target.txt")
  end

  def self.const_key(name)
    return name.is_a?(Symbol) ? name : name.to_s.to_sym
  end

  def self.quote_arg(value)
    return "\"" + value.to_s.gsub("\"", "") + "\""
  rescue Exception
    return "\"\""
  end

  def self.open_path(path)
    path = path.to_s
    params = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " + quote_arg(path)
    if defined?(Win32API)
      shell = Win32API.new("shell32", "ShellExecuteA", "LPPPPI", "I")
      result = shell.call(0, "open", "powershell.exe", params, nil, 0)
      return true if result && result.to_i > 32
    end
    system("cmd /c start \"\" powershell.exe " + params)
    return true
  rescue Exception
    return false
  end

  def self.ensure_dir(path)
    path = path.to_s.gsub("\\", "/")
    parts = path.split("/")
    current = ""
    for part in parts
      next if part == ""
      if current == ""
        current = part
      else
        current += "/" + part
      end
      next if part =~ /\A[A-Za-z]:\z/
      Dir.mkdir(current) if !FileTest.directory?(current)
    end
  rescue Exception
  end

  def self.ensure_runtime
    if defined?(SebiLinkPaths)
      SebiLinkPaths.migrate_runtime_dir(File.expand_path("multiplayer/save-editor/runtime"), runtime_dir)
    end
    ensure_dir(runtime_dir)
  end

  def self.atomic_write(path, text)
    ensure_dir(File.dirname(path))
    tmp = path.to_s + ".tmp"
    File.open(tmp, "wb") { |file| file.write(text.to_s) }
    begin
      File.delete(path) if FileTest.exist?(path)
    rescue Exception
    end
    begin
      File.rename(tmp, path)
    rescue Exception
      File.open(path, "wb") { |file| file.write(text.to_s) }
      begin
        File.delete(tmp) if FileTest.exist?(tmp)
      rescue Exception
      end
    end
  rescue Exception
  end

  def self.json_escape(value)
    text = value.to_s
    text = text.gsub(/\\/) { "\\\\" }
    text = text.gsub(/"/) { "\\\"" }
    text = text.gsub(/\r/) { "\\r" }
    text = text.gsub(/\n/) { "\\n" }
    text = text.gsub(/\t/) { "\\t" }
    return "\"" + text + "\""
  rescue Exception
    return "\"\""
  end

  def self.json(value)
    case value
    when NilClass
      return "null"
    when TrueClass
      return "true"
    when FalseClass
      return "false"
    when Numeric
      return value.to_s
    when Array
      return "[" + value.collect { |item| json(item) }.join(",") + "]"
    when Hash
      parts = []
      value.each { |key, item| parts.push(json_escape(key.to_s) + ":" + json(item)) }
      return "{" + parts.join(",") + "}"
    else
      return json_escape(value)
    end
  rescue Exception
    return "null"
  end

  def self.safe(default_value = nil)
    return yield
  rescue Exception
    return default_value
  end

  def self.clamp(value, min_value, max_value)
    value = value.to_i
    value = min_value if value < min_value
    value = max_value if value > max_value
    return value
  end

  def self.name_from(mod_name, id)
    mod = Object.const_get(const_key(mod_name))
    return mod.getName(id.to_i).to_s
  rescue Exception
    return ""
  end

  def self.max_const_value(mod_name, default_value)
    return default_value if !Object.const_defined?(const_key(mod_name))
    mod = Object.const_get(const_key(mod_name))
    return safe(default_value) { mod.maxValue.to_i }
  rescue Exception
    return default_value
  end

  def self.named_list(mod_name, default_max = 0)
    ret = []
    return ret if !Object.const_defined?(const_key(mod_name))
    mod = Object.const_get(const_key(mod_name))
    max = safe(default_max) { mod.maxValue }
    max = default_max if !max || max.to_i <= 0
    for i in 1..max.to_i
      name = safe("") { mod.getName(i).to_s }
      next if !name || name == ""
      ret.push({ "id" => i, "name" => name })
    end
    return ret
  rescue Exception
    return ret || []
  end

  def self.move_list
    return @move_list if @move_list
    ret = []
    for entry in named_list("PBMoves", 0)
      id = entry["id"].to_i
      if defined?(SebiMoveInfo)
        detail = SebiMoveInfo.details(id)
        entry["type"] = detail["type"]
        entry["typeName"] = detail["typeName"]
        entry["category"] = detail["category"]
        entry["categoryName"] = detail["categoryName"]
        entry["power"] = detail["power"]
        entry["accuracy"] = detail["accuracy"]
        entry["pp"] = detail["pp"]
        entry["description"] = detail["description"]
      elsif defined?(PBMoveData)
        entry["type"] = safe(-1) { PBMoveData.new(id).type.to_i }
      end
      ret.push(entry)
    end
    @move_list = ret
    return @move_list
  rescue Exception
    @move_list = named_list("PBMoves", 0)
    return @move_list
  end

  def self.base_stats_for_pokemon(pokemon)
    arr = safe(nil) { pokemon.baseStats }
    ret = []
    if arr && arr.length >= 6
      # Editor order: HP, Atk, Def, SpA, SpD, Spe.
      ret = [arr[0].to_i, arr[1].to_i, arr[2].to_i, arr[4].to_i, arr[5].to_i, arr[3].to_i]
    end
    return ret if ret.length >= 6
    return [0, 0, 0, 0, 0, 0]
  rescue Exception
    return [0, 0, 0, 0, 0, 0]
  end

  def self.learnable_move_ids(pokemon)
    ret = []
    return ret if !pokemon
    list = safe([]) { pokemon.getMoveList }
    list.each do |entry|
      move_id = 0
      if entry.is_a?(Array)
        move_id = entry[1].to_i
      else
        move_id = entry.to_i
      end
      ret.push(move_id) if move_id > 0
    end
    moves = safe([]) { pokemon.moves }
    moves.each do |move|
      id = safe(0) { move.id.to_i }
      ret.push(id) if id > 0
    end
    return ret.uniq
  rescue Exception
    return []
  end

  def self.compatible_move_ids(species)
    species = species.to_i
    return [] if species <= 0
    @compatible_move_cache ||= {}
    return @compatible_move_cache[species] if @compatible_move_cache.has_key?(species)
    ret = []
    if defined?(pbSpeciesCompatible?)
      for entry in move_list
        id = entry["id"].to_i
        next if id <= 0
        ret.push(id) if safe(false) { pbSpeciesCompatible?(species, id) ? true : false }
      end
    end
    @compatible_move_cache[species] = ret.uniq
    return @compatible_move_cache[species]
  rescue Exception
    return []
  end

  def self.item_list
    max = 0
    max = $ItemData.length - 1 if defined?($ItemData) && $ItemData
    ret = []
    for entry in named_list("PBItems", max)
      id = entry["id"]
      entry["pocket"] = safe(0) { pbGetPocket(id).to_i }
      ret.push(entry)
    end
    return ret
  rescue Exception
    return []
  end

  def self.status_list
    ret = []
    for i in 0..9
      name = name_from("PBStatuses", i)
      name = "Normal" if i == 0 && name == ""
      ret.push({ "id" => i, "name" => name }) if name && name != ""
    end
    return ret
  rescue Exception
    return []
  end

  def self.write_data_file
    ensure_runtime
    data = {
      "generatedAt" => Time.now.to_s,
      "species" => named_list("PBSpecies", 0),
      "items" => item_list,
      "moves" => move_list,
      "abilities" => named_list("PBAbilities", 0),
      "natures" => named_list("PBNatures", 24),
      "ribbons" => named_list("PBRibbons", 0),
      "statuses" => status_list
    }
    atomic_write(data_path, json(data))
    @data_written = true
  rescue Exception
  end

  def self.data_file_ready?
    return false if !FileTest.exist?(data_path)
    return false if (File.size(data_path) rescue 0) < 100
    return true
  rescue Exception
    return false
  end

  def self.external_editing?
    return ((@external_edit_path && @external_edit_path.to_s != "" && @external_edit_sections) ? true : false)
  rescue Exception
    return false
  end

  def self.clear_external_edit
    @external_edit_path = ""
    @external_edit_sections = nil
  rescue Exception
  end

  def self.with_external_sections
    sections = @external_edit_sections || {}
    old_trainer = $Trainer
    old_game_system = $game_system
    old_pokemon_system = $PokemonSystem
    old_switches = $game_switches
    old_variables = $game_variables
    old_self_switches = $game_self_switches
    old_screen = $game_screen
    old_map_factory = $MapFactory
    old_player = $game_player
    old_global = $PokemonGlobal
    old_pokemon_map = $PokemonMap
    old_bag = $PokemonBag
    old_storage = $PokemonStorage
    old_game_map = $game_map
    begin
      $Trainer = sections["trainer"]
      $game_system = sections["gameSystem"]
      $PokemonSystem = sections["pokemonSystem"]
      $game_switches = sections["switches"]
      $game_variables = sections["variables"]
      $game_self_switches = sections["selfSwitches"]
      $game_screen = sections["screen"]
      $MapFactory = sections["mapFactory"]
      $game_player = sections["player"]
      $PokemonGlobal = sections["global"]
      $PokemonMap = sections["pokemonMap"]
      $PokemonBag = sections["bag"]
      $PokemonStorage = sections["storage"]
      $game_map = nil
      return yield
    ensure
      $Trainer = old_trainer
      $game_system = old_game_system
      $PokemonSystem = old_pokemon_system
      $game_switches = old_switches
      $game_variables = old_variables
      $game_self_switches = old_self_switches
      $game_screen = old_screen
      $MapFactory = old_map_factory
      $game_player = old_player
      $PokemonGlobal = old_global
      $PokemonMap = old_pokemon_map
      $PokemonBag = old_bag
      $PokemonStorage = old_storage
      $game_map = old_game_map
    end
  rescue Exception
    return nil
  end

  def self.delete_runtime_file(path)
    begin
      File.delete(path) if path && FileTest.exist?(path)
    rescue Exception
    end
  end

  def self.reset_for_save_change
    @active = false
    @last_snapshot_frame = -9999
    clear_external_edit
    delete_runtime_file(command_path)
    delete_runtime_file(result_path)
    delete_runtime_file(state_path)
    delete_runtime_file(open_after_load_path)
    delete_runtime_file(edit_target_path)
    delete_runtime_file(alive_path)
  rescue Exception
  end

  def self.mark_window_opening
    @window_started_frame = Graphics.frame_count rescue 0
    delete_runtime_file(alive_path)
  rescue Exception
  end

  def self.window_alive?
    frame = Graphics.frame_count rescue 0
    return true if @window_started_frame && frame - @window_started_frame < 600
    return false if !FileTest.exist?(alive_path)
    return (Time.now - File.mtime(alive_path)) < 8
  rescue Exception
    return true
  end

  def self.move_data(move, slot)
    if !move
      return { "slot" => slot, "id" => 0, "name" => "", "pp" => 0, "totalpp" => 0, "ppup" => 0 }
    end
    id = safe(0) { move.id.to_i }
    return {
      "slot" => slot,
      "id" => id,
      "name" => name_from("PBMoves", id),
      "pp" => safe(0) { move.pp.to_i },
      "totalpp" => safe(0) { move.totalpp.to_i },
      "ppup" => safe(0) { move.ppup.to_i }
    }
  rescue Exception
    return { "slot" => slot, "id" => 0, "name" => "", "pp" => 0, "totalpp" => 0, "ppup" => 0 }
  end

  def self.stat_array(pokemon, key)
    source = safe([]) { pokemon.send(key) }
    ret = []
    for i in 0...6
      ret.push(safe(0) { source[i].to_i })
    end
    return ret
  rescue Exception
    return [0, 0, 0, 0, 0, 0]
  end

  def self.pokemon_data(pokemon, loc, index, box = nil, slot = nil)
    return nil if !pokemon
    species = safe(0) { pokemon.species.to_i }
    item = safe(0) { pokemon.item.to_i }
    ability = safe(0) { pokemon.ability.to_i }
    nature = safe(0) { pokemon.nature.to_i }
    moves = []
    for i in 0...4
      moves.push(move_data(safe(nil) { pokemon.moves[i] }, i))
    end
    return {
      "loc" => loc,
      "index" => index,
      "box" => box,
      "slot" => slot,
      "species" => species,
      "speciesName" => name_from("PBSpecies", species),
      "nickname" => safe("") { pokemon.name.to_s },
      "level" => safe(1) { pokemon.level.to_i },
      "exp" => safe(0) { pokemon.exp.to_i },
      "hp" => safe(0) { pokemon.hp.to_i },
      "totalhp" => safe(0) { pokemon.totalhp.to_i },
      "status" => safe(0) { pokemon.status.to_i },
      "statusCount" => safe(0) { pokemon.statusCount.to_i },
      "item" => item,
      "itemName" => item > 0 ? name_from("PBItems", item) : "",
      "ability" => ability,
      "abilityName" => ability > 0 ? name_from("PBAbilities", ability) : "",
      "abilityflag" => safe(nil) { pokemon.abilityflag },
      "nature" => nature,
      "natureName" => name_from("PBNatures", nature),
      "natureflag" => safe(nil) { pokemon.natureflag },
      "gender" => safe(2) { pokemon.gender.to_i },
      "genderflag" => safe(nil) { pokemon.genderflag },
      "shiny" => safe(false) { pokemon.isShiny? ? true : false },
      "shinyflag" => safe(nil) { pokemon.shinyflag },
      "happiness" => safe(0) { pokemon.happiness.to_i },
      "pokerus" => safe(0) { pokemon.pokerus.to_i },
      "eggsteps" => safe(0) { pokemon.eggsteps.to_i },
      "form" => safe(0) { pokemon.form.to_i },
      "baseStats" => base_stats_for_pokemon(pokemon),
      "iv" => stat_array(pokemon, :iv),
      "ev" => stat_array(pokemon, :ev),
      "stats" => {
        "attack" => safe(0) { pokemon.attack.to_i },
        "defense" => safe(0) { pokemon.defense.to_i },
        "speed" => safe(0) { pokemon.speed.to_i },
        "spatk" => safe(0) { pokemon.spatk.to_i },
        "spdef" => safe(0) { pokemon.spdef.to_i }
      },
      "learnedMoves" => learnable_move_ids(pokemon),
      "learnableMoves" => [],
      "moves" => moves,
      "ot" => safe("") { pokemon.ot.to_s },
      "otgender" => safe(2) { pokemon.otgender.to_i },
      "trainerID" => safe(0) { pokemon.trainerID.to_i },
      "personalID" => safe(0) { pokemon.personalID.to_i },
      "language" => safe(0) { pokemon.language.to_i },
      "obtainMode" => safe(0) { pokemon.obtainMode.to_i },
      "obtainLevel" => safe(0) { pokemon.obtainLevel.to_i },
      "obtainMap" => safe(0) { pokemon.obtainMap.to_i },
      "obtainText" => safe("") { pokemon.obtainText.to_s },
      "hatchedMap" => safe(0) { pokemon.hatchedMap.to_i },
      "ballused" => safe(0) { pokemon.ballused.to_i },
      "markings" => safe(0) { pokemon.markings.to_i },
      "expshare" => safe(false) { pokemon.expshare ? true : false },
      "contest" => {
        "cool" => safe(0) { pokemon.cool.to_i },
        "beauty" => safe(0) { pokemon.beauty.to_i },
        "cute" => safe(0) { pokemon.cute.to_i },
        "smart" => safe(0) { pokemon.smart.to_i },
        "tough" => safe(0) { pokemon.tough.to_i },
        "sheen" => safe(0) { pokemon.sheen.to_i }
      },
      "firstmoves" => safe([]) { pokemon.firstmoves || [] },
      "ribbons" => safe([]) { pokemon.ribbons || [] },
      "ribbonCount" => safe(0) { pokemon.ribbonCount.to_i },
      "timeReceived" => safe(0) { pokemon.instance_variable_get("@timeReceived").to_i },
      "timeEggHatched" => safe(0) { pokemon.instance_variable_get("@timeEggHatched").to_i },
      "isEgg" => safe(false) { pokemon.isEgg? ? true : false }
    }
  rescue Exception
    return nil
  end

  def self.party_data
    ret = []
    return ret if !$Trainer || !$Trainer.party
    for i in 0...$Trainer.party.length
      data = pokemon_data($Trainer.party[i], "party", i, nil, nil)
      ret.push(data) if data
    end
    return ret
  rescue Exception
    return []
  end

  def self.storage_data
    ret = { "currentBox" => 0, "boxes" => [] }
    return ret if !defined?($PokemonStorage) || !$PokemonStorage
    ret["currentBox"] = safe(0) { $PokemonStorage.currentBox.to_i }
    boxes = safe([]) { $PokemonStorage.boxes }
    for b in 0...boxes.length
      box = boxes[b]
      next if !box
      pokemon = []
      for s in 0...box.length
        data = pokemon_data(box[s], "box", s, b, s)
        pokemon.push(data) if data
      end
      ret["boxes"].push({
        "index" => b,
        "name" => safe("Caja " + (b + 1).to_s) { box.name.to_s },
        "length" => safe(30) { box.length.to_i },
        "count" => pokemon.length,
        "pokemon" => pokemon
      })
    end
    return ret
  rescue Exception
    return ret
  end

  def self.bag_data
    ret = []
    return ret if !$PokemonBag
    pockets = safe(nil) { $PokemonBag.pockets }
    if !pockets || !pockets.respond_to?(:length) || pockets.length <= 0
      pockets = safe([]) { $PokemonBag.instance_variable_get("@pockets") }
    end
    for pocket in 0...pockets.length
      pocket_items = pockets[pocket]
      next if !pocket_items
      for slot in 0...pocket_items.length
        item = pocket_items[slot]
        next if !item || item[0].to_i <= 0
        id = item[0].to_i
        ret.push({
          "pocket" => pocket,
          "slot" => slot,
          "id" => id,
          "name" => name_from("PBItems", id),
          "quantity" => item[1].to_i
        })
      end
    end
    return ret
  rescue Exception
    return []
  end

  def self.achievement_status_name(status)
    hidden_status = defined?(LOGRO_OCULTO) ? LOGRO_OCULTO : 1
    completed_status = defined?(LOGRO_COMPLETADO) ? LOGRO_COMPLETADO : 3
    case status.to_i
    when hidden_status
      return "Oculto"
    when completed_status
      return "Completado"
    else
      return "Activo"
    end
  rescue Exception
    return status.to_s
  end

  def self.achievements_data
    ret = []
    return ret if !defined?(LOGROS) || !$PokemonGlobal
    safe(nil) { $PokemonGlobal.loadLogros if $PokemonGlobal.respond_to?(:loadLogros) }
    for i in 0...LOGROS.length
      logro = LOGROS[i]
      status = safe(2) {
        if defined?(getLogro)
          getLogro(i).to_i
        elsif $PokemonGlobal.respond_to?(:logros) && $PokemonGlobal.logros
          $PokemonGlobal.logros[i].to_i
        else
          logro.length >= 3 ? logro[2].to_i : 2
        end
      }
      ret.push({
        "index" => i,
        "name" => safe("Logro " + (i + 1).to_s) { logro[0].to_s },
        "description" => safe("") { logro[1].to_s },
        "status" => status,
        "statusName" => achievement_status_name(status)
      })
    end
    return ret
  rescue Exception
    return []
  end

  def self.switches_data
    ret = { "max" => 0, "on" => [] }
    return ret if !$game_switches
    data = safe([]) { $game_switches.instance_variable_get("@data") }
    ret["max"] = data.length - 1
    for i in 1...data.length
      ret["on"].push(i) if data[i]
    end
    return ret
  rescue Exception
    return ret
  end

  def self.variables_data
    ret = { "max" => 0, "values" => [] }
    return ret if !$game_variables
    data = safe([]) { $game_variables.instance_variable_get("@data") }
    ret["max"] = data.length - 1
    for i in 1...data.length
      value = data[i]
      next if value == nil || value == 0 || value == ""
      ret["values"].push({ "id" => i, "value" => value.to_s, "type" => value.class.to_s })
    end
    return ret
  rescue Exception
    return ret
  end

  def self.trainer_data
    return { "loaded" => false } if !$Trainer
    badges = []
    safe([]) { $Trainer.badges }.each_with_index { |value, i| badges.push({ "index" => i, "value" => value ? true : false }) }
    return {
      "loaded" => true,
      "name" => safe("") { $Trainer.name.to_s },
      "id" => safe(0) { $Trainer.id.to_i },
      "publicID" => safe(0) { $Trainer.publicID.to_i },
      "secretID" => safe(0) { $Trainer.secretID.to_i },
      "money" => safe(0) { $Trainer.money.to_i },
      "trainertype" => safe(0) { $Trainer.trainertype.to_i },
      "outfit" => safe(0) { $Trainer.outfit.to_i },
      "language" => safe(0) { $Trainer.language.to_i },
      "pokedex" => safe(false) { $Trainer.pokedex ? true : false },
      "pokegear" => safe(false) { $Trainer.pokegear ? true : false },
      "badges" => badges,
      "numbadges" => safe(0) { $Trainer.numbadges.to_i },
      "pokemonCount" => safe(0) { $Trainer.pokemonCount.to_i },
      "ablePokemonCount" => safe(0) { $Trainer.ablePokemonCount.to_i }
    }
  rescue Exception
    return { "loaded" => false }
  end

  def self.external_state_data
    sections = @external_edit_sections || {}
    map_id = safe(0) { sections["mapId"].to_i }
    player = sections["player"]
    data = with_external_sections do
      {
        "version" => 1,
        "generatedAt" => Time.now.to_s,
        "frame" => safe(0) { sections["frame"].to_i },
        "loaded" => true,
        "editMode" => "file",
        "editPath" => @external_edit_path.to_s,
        "inBattle" => false,
        "map" => {
          "id" => map_id,
          "name" => safe("") { pbGetMapNameFromId(map_id).to_s },
          "x" => safe(0) { player.x.to_i },
          "y" => safe(0) { player.y.to_i },
          "direction" => safe(0) { player.direction.to_i }
        },
        "global" => {
          "nuzlocke" => safe(false) { $PokemonGlobal.nuzlocke ? true : false },
          "playerID" => safe(0) { $PokemonGlobal.playerID.to_i }
        },
        "trainer" => trainer_data,
        "party" => party_data,
        "storage" => storage_data,
        "bag" => bag_data,
        "achievements" => achievements_data,
        "switches" => switches_data,
        "variables" => variables_data
      }
    end
    return data || { "version" => 1, "loaded" => false, "error" => "No se pudo leer el archivo externo." }
  rescue Exception
    return { "version" => 1, "loaded" => false, "error" => $!.message.to_s }
  end

  def self.live_state_data
    return {
      "version" => 1,
      "generatedAt" => Time.now.to_s,
      "frame" => safe(0) { Graphics.frame_count.to_i },
      "loaded" => $Trainer ? true : false,
      "inBattle" => ($game_temp && $game_temp.in_battle) ? true : false,
      "map" => {
        "id" => safe(0) { $game_map.map_id.to_i },
        "name" => safe("") { $game_map.name.to_s },
        "x" => safe(0) { $game_player.x.to_i },
        "y" => safe(0) { $game_player.y.to_i },
        "direction" => safe(0) { $game_player.direction.to_i }
      },
      "global" => {
        "nuzlocke" => safe(false) { $PokemonGlobal.nuzlocke ? true : false },
        "playerID" => safe(0) { $PokemonGlobal.playerID.to_i }
      },
      "trainer" => trainer_data,
      "party" => party_data,
      "storage" => storage_data,
      "bag" => bag_data,
      "achievements" => achievements_data,
      "switches" => switches_data,
      "variables" => variables_data
    }
  rescue Exception
    return { "version" => 1, "loaded" => false, "error" => $!.message.to_s }
  end

  def self.state_data
    return external_state_data if external_editing?
    return live_state_data
  rescue Exception
    return { "version" => 1, "loaded" => false, "error" => $!.message.to_s }
  end

  def self.write_state_file(force = false)
    frame = safe(0) { Graphics.frame_count.to_i }
    return if !force && @last_snapshot_frame && frame - @last_snapshot_frame < SNAPSHOT_FRAMES
    ensure_runtime
    atomic_write(state_path, json(state_data))
    @last_snapshot_frame = frame
  rescue Exception
  end

  def self.percent_decode(value)
    value = value.to_s.gsub("+", " ")
    return value.gsub(/%([0-9A-Fa-f]{2})/) { $1.to_i(16).chr }
  rescue Exception
    return value.to_s
  end

  def self.parse_command(line)
    parts = line.to_s.gsub(/\r|\n/, "").split("|")
    ret = { "seq" => parts[0].to_s, "cmd" => parts[1].to_s, "args" => {} }
    for i in 2...parts.length
      pair = parts[i].split("=", 2)
      next if pair.length < 2
      ret["args"][pair[0].to_s] = percent_decode(pair[1].to_s)
    end
    return ret
  rescue Exception
    return nil
  end

  def self.bool_value(value)
    text = value.to_s.downcase
    return true if text == "true" || text == "1" || text == "yes" || text == "on"
    return false
  end

  def self.item_id(value)
    value = value.to_s.strip
    return value.to_i if value =~ /\A\d+\z/
    return getID(PBItems, value.to_sym) if defined?(PBItems) && defined?(getID)
    return 0
  rescue Exception
    return 0
  end

  def self.locate_pokemon(args)
    loc = args["loc"].to_s
    if loc == "party"
      index = args["index"].to_i
      return nil if !$Trainer || !$Trainer.party || index < 0 || index >= $Trainer.party.length
      return $Trainer.party[index]
    elsif loc == "box"
      box = args["box"].to_i
      slot = args["slot"].to_i
      return nil if !defined?($PokemonStorage) || !$PokemonStorage
      return nil if box < 0 || box >= $PokemonStorage.maxBoxes
      return nil if slot < 0 || slot >= $PokemonStorage.maxPokemon(box)
      return $PokemonStorage[box, slot]
    end
    return nil
  rescue Exception
    return nil
  end

  def self.source_key(args)
    loc = args["loc"].to_s
    if loc == "party"
      return "party:" + args["index"].to_i.to_s
    elsif loc == "box"
      return "box:" + args["box"].to_i.to_s + ":" + args["slot"].to_i.to_s
    end
    return ""
  rescue Exception
    return ""
  end

  def self.destination_key(args)
    loc = args["destLoc"].to_s
    loc = args["loc"].to_s if loc == ""
    if loc == "party"
      index = args.has_key?("destIndex") ? args["destIndex"].to_i : -1
      return index >= 0 ? "party:" + index.to_s : ""
    elsif loc == "box"
      box = args.has_key?("destBox") ? args["destBox"].to_i : safe(0) { $PokemonStorage.currentBox.to_i }
      slot = args.has_key?("destSlot") ? args["destSlot"].to_i : -1
      return slot >= 0 ? "box:" + box.to_s + ":" + slot.to_s : ""
    end
    return ""
  rescue Exception
    return ""
  end

  def self.delete_pokemon_at(args)
    loc = args["loc"].to_s
    if loc == "party"
      index = args["index"].to_i
      return false if !$Trainer || !$Trainer.party || index < 0 || index >= $Trainer.party.length
      $Trainer.party.delete_at(index)
      $Trainer.party.compact!
      return true
    elsif loc == "box"
      box = args["box"].to_i
      slot = args["slot"].to_i
      return false if !defined?($PokemonStorage) || !$PokemonStorage
      return false if box < 0 || box >= $PokemonStorage.maxBoxes
      return false if slot < 0 || slot >= $PokemonStorage.maxPokemon(box)
      $PokemonStorage[box, slot] = nil
      return true
    end
    return false
  rescue Exception
    return false
  end

  def self.place_pokemon(args, pokemon)
    return [false, "Pokemon invalido."] if !pokemon
    loc = args["destLoc"].to_s
    loc = args["loc"].to_s if loc == ""
    replace = bool_value(args["replace"])
    if loc == "party"
      return [false, "Equipo no disponible."] if !$Trainer || !$Trainer.party
      index = args.has_key?("destIndex") ? args["destIndex"].to_i : -1
      if index >= 0
        return [false, "Indice de equipo invalido."] if index >= 6
        if index < $Trainer.party.length
          return [false, "Ese hueco del equipo esta ocupado."] if $Trainer.party[index] && !replace
          $Trainer.party[index] = pokemon
        else
          return [false, "El equipo esta lleno."] if $Trainer.party.length >= 6
          $Trainer.party.push(pokemon)
        end
      else
        return [false, "El equipo esta lleno."] if $Trainer.party.length >= 6
        $Trainer.party.push(pokemon)
      end
      $Trainer.party.compact!
      return [true, "Pokemon colocado en el equipo."]
    elsif loc == "box"
      return [false, "PC no disponible."] if !defined?($PokemonStorage) || !$PokemonStorage
      box = args.has_key?("destBox") ? args["destBox"].to_i : safe(0) { $PokemonStorage.currentBox.to_i }
      return [false, "Caja invalida."] if box < 0 || box >= $PokemonStorage.maxBoxes
      slot = args.has_key?("destSlot") ? args["destSlot"].to_i : -1
      if slot < 0
        slot = $PokemonStorage.pbFirstFreePos(box)
        return [false, "La caja esta llena."] if slot < 0
      end
      return [false, "Slot invalido."] if slot < 0 || slot >= $PokemonStorage.maxPokemon(box)
      return [false, "Ese slot del PC esta ocupado."] if $PokemonStorage[box, slot] && !replace
      pokemon.heal if safe(false) { !pokemon.isEgg? }
      pokemon.formTime = nil if pokemon.respond_to?("formTime") && pokemon.formTime
      $PokemonStorage[box, slot] = pokemon
      return [true, "Pokemon colocado en el PC."]
    end
    return [false, "Destino invalido."]
  rescue Exception
    return [false, "Error colocando Pokemon: " + $!.message.to_s]
  end

  def self.clone_pokemon(pokemon)
    return Marshal.load(Marshal.dump(pokemon))
  rescue Exception
    return nil
  end

  def self.set_array_value(array, index, value, min_value, max_value)
    return if !array || index < 0 || index >= 6
    array[index] = clamp(value, min_value, max_value)
  rescue Exception
  end

  def self.parse_int_list(value, min_value = 0, max_value = 999999)
    ret = []
    value.to_s.split(",").each do |part|
      next if part.to_s.strip == ""
      ret.push(clamp(part, min_value, max_value))
    end
    return ret
  rescue Exception
    return []
  end

  def self.set_pokemon_form(pokemon, value)
    value = [value.to_i, 0].max
    if pokemon.respond_to?(:form=)
      pokemon.form = value
    elsif pokemon.respond_to?(:formNoCall=)
      pokemon.formNoCall = value
    else
      pokemon.instance_variable_set("@form", value)
    end
  rescue Exception
  end

  def self.max_pokemon_level
    return PBExperience::MAXLEVEL if defined?(PBExperience) && defined?(PBExperience::MAXLEVEL)
    return MAXIMUMLEVEL if Object.const_defined?(:MAXIMUMLEVEL)
    return 100
  rescue Exception
    return 100
  end

  def self.level_from_experience(pokemon, exp)
    return nil if !pokemon || !defined?(PBExperience) || !PBExperience.respond_to?(:pbGetLevelFromExperience)
    growth = safe(nil) { pokemon.growthrate }
    return nil if growth == nil
    return PBExperience.pbGetLevelFromExperience([exp.to_i, 0].max, growth).to_i
  rescue Exception
    return nil
  end

  def self.apply_pokemon_level_and_exp(pokemon, args)
    return if !pokemon || (!args.has_key?("level") && !args.has_key?("exp"))
    target_level = nil
    if args.has_key?("level")
      target_level = clamp(args["level"], 1, max_pokemon_level)
      pokemon.level = target_level
    end
    if args.has_key?("exp")
      requested_exp = [args["exp"].to_i, 0].max
      if target_level == nil || level_from_experience(pokemon, requested_exp) == target_level
        pokemon.exp = requested_exp
      end
    end
  rescue Exception
  end

  def self.apply_pokemon_fields(pokemon, args)
    pokemon.species = clamp(args["species"], 1, max_const_value("PBSpecies", 9999)) if args.has_key?("species")
    pokemon.name = args["nickname"].to_s if args.has_key?("nickname")
    pokemon.status = clamp(args["status"], 0, 9) if args.has_key?("status")
    pokemon.statusCount = [args["statusCount"].to_i, 0].max if args.has_key?("statusCount")
    pokemon.happiness = clamp(args["happiness"], 0, 255) if args.has_key?("happiness")
    pokemon.item = item_id(args["item"]) if args.has_key?("item")
    pokemon.pokerus = clamp(args["pokerus"], 0, 255) if args.has_key?("pokerus")
    set_pokemon_form(pokemon, args["form"].to_i) if args.has_key?("form")
    pokemon.natureflag = args["natureflag"].to_i < 0 ? nil : clamp(args["natureflag"], 0, 24) if args.has_key?("natureflag")
    pokemon.abilityflag = args["abilityflag"].to_i < 0 ? nil : clamp(args["abilityflag"], 0, 2) if args.has_key?("abilityflag")
    pokemon.genderflag = args["genderflag"].to_i < 0 ? nil : clamp(args["genderflag"], 0, 1) if args.has_key?("genderflag")
    pokemon.shinyflag = bool_value(args["shiny"]) if args.has_key?("shiny")
    pokemon.eggsteps = [args["eggsteps"].to_i, 0].max if args.has_key?("eggsteps")
    pokemon.ot = args["ot"].to_s if args.has_key?("ot")
    pokemon.otgender = clamp(args["otgender"], 0, 3) if args.has_key?("otgender")
    pokemon.trainerID = clamp(args["trainerID"], 0, 0xffffffff) if args.has_key?("trainerID")
    pokemon.personalID = clamp(args["personalID"], 0, 0xffffffff) if args.has_key?("personalID")
    pokemon.language = clamp(args["language"], 0, 9999) if args.has_key?("language")
    pokemon.obtainMode = clamp(args["obtainMode"], 0, 9) if args.has_key?("obtainMode")
    pokemon.obtainLevel = clamp(args["obtainLevel"], 0, defined?(PBExperience) ? PBExperience::MAXLEVEL : 100) if args.has_key?("obtainLevel")
    pokemon.obtainMap = [args["obtainMap"].to_i, 0].max if args.has_key?("obtainMap")
    pokemon.obtainText = args["obtainText"].to_s if args.has_key?("obtainText")
    pokemon.hatchedMap = [args["hatchedMap"].to_i, 0].max if args.has_key?("hatchedMap")
    pokemon.ballused = [args["ballused"].to_i, 0].max if args.has_key?("ballused")
    pokemon.markings = clamp(args["markings"], 0, 15) if args.has_key?("markings")
    pokemon.expshare = bool_value(args["expshare"]) if args.has_key?("expshare") && pokemon.respond_to?(:expshare=)
    pokemon.cool = clamp(args["cool"], 0, 255) if args.has_key?("cool")
    pokemon.beauty = clamp(args["beauty"], 0, 255) if args.has_key?("beauty")
    pokemon.cute = clamp(args["cute"], 0, 255) if args.has_key?("cute")
    pokemon.smart = clamp(args["smart"], 0, 255) if args.has_key?("smart")
    pokemon.tough = clamp(args["tough"], 0, 255) if args.has_key?("tough")
    pokemon.sheen = clamp(args["sheen"], 0, 255) if args.has_key?("sheen")
    pokemon.firstmoves = parse_int_list(args["firstmoves"], 1, max_const_value("PBMoves", 9999)) if args.has_key?("firstmoves")
    pokemon.ribbons = parse_int_list(args["ribbons"], 1, max_const_value("PBRibbons", 9999)) if args.has_key?("ribbons")
    pokemon.timeReceived = [args["timeReceived"].to_i, 0].max if args.has_key?("timeReceived")
    pokemon.timeEggHatched = [args["timeEggHatched"].to_i, 0].max if args.has_key?("timeEggHatched")
    for i in 0...6
      set_array_value(pokemon.iv, i, args["iv" + i.to_s], 0, 31) if args.has_key?("iv" + i.to_s)
      set_array_value(pokemon.ev, i, args["ev" + i.to_s], 0, 252) if args.has_key?("ev" + i.to_s)
    end
    for i in 0...4
      move_key = "move" + i.to_s
      pp_key = "move" + i.to_s + "pp"
      ppup_key = "move" + i.to_s + "ppup"
      if args.has_key?(move_key)
        move_id = clamp(args[move_key], 0, max_const_value("PBMoves", 9999))
        pokemon.moves[i] = PBMove.new(move_id)
      end
      if args.has_key?(ppup_key) && pokemon.moves[i]
        pokemon.moves[i].ppup = clamp(args[ppup_key], 0, 3) if pokemon.moves[i].respond_to?(:ppup=)
      end
      if args.has_key?(pp_key) && pokemon.moves[i]
        pokemon.moves[i].pp = clamp(args[pp_key], 0, pokemon.moves[i].totalpp)
      end
    end
    apply_pokemon_level_and_exp(pokemon, args)
    pokemon.calcStats
    pokemon.hp = clamp(args["hp"], 0, pokemon.totalhp) if args.has_key?("hp")
  rescue Exception
    raise
  end

  def self.apply_trainer(args)
    return [false, "No hay partida cargada."] if !$Trainer
    $Trainer.name = args["name"].to_s if args.has_key?("name")
    $Trainer.money = clamp(args["money"], 0, Object.const_defined?(:MAXMONEY) ? MAXMONEY : 9999999) if args.has_key?("money")
    $Trainer.id = clamp(args["id"], 0, 0x7fffffff) if args.has_key?("id")
    $Trainer.trainertype = clamp(args["trainertype"], 0, 9999) if args.has_key?("trainertype")
    $Trainer.outfit = clamp(args["outfit"], 0, 9999) if args.has_key?("outfit")
    $Trainer.language = clamp(args["language"], 0, 9999) if args.has_key?("language")
    $Trainer.pokedex = bool_value(args["pokedex"]) if args.has_key?("pokedex")
    $Trainer.pokegear = bool_value(args["pokegear"]) if args.has_key?("pokegear")
    if args.has_key?("nuzlocke") && $PokemonGlobal
      $PokemonGlobal.nuzlocke = bool_value(args["nuzlocke"])
    end
    if args.has_key?("badges")
      enabled = {}
      args["badges"].to_s.split(",").each { |i| enabled[i.to_i] = true }
      $Trainer.badges = [] if !$Trainer.badges
      max = [$Trainer.badges.length, 16].max
      for i in 0...max
        $Trainer.badges[i] = enabled[i] ? true : false
      end
    end
    return [true, "Entrenador actualizado."]
  rescue Exception
    return [false, "Error entrenador: " + $!.message.to_s]
  end

  def self.apply_pokemon(args)
    pokemon = locate_pokemon(args)
    return [false, "Pokemon no encontrado."] if !pokemon
    apply_pokemon_fields(pokemon, args)
    return [true, "Pokemon actualizado."]
  rescue Exception
    return [false, "Error Pokemon: " + $!.message.to_s]
  end

  def self.apply_pokemon_create(args)
    return [false, "No hay partida cargada."] if !$Trainer
    species = clamp(args["species"], 1, max_const_value("PBSpecies", 9999))
    level = clamp(args["level"], 1, defined?(PBExperience) ? PBExperience::MAXLEVEL : 100)
    pokemon = PokeBattle_Pokemon.new(species, level, $Trainer)
    apply_pokemon_fields(pokemon, args)
    return place_pokemon(args, pokemon)
  rescue Exception
    return [false, "Error creando Pokemon: " + $!.message.to_s]
  end

  def self.apply_pokemon_delete(args)
    return [false, "No se puede borrar el ultimo Pokemon del equipo."] if args["loc"].to_s == "party" && $Trainer && $Trainer.party && $Trainer.party.length <= 1
    return delete_pokemon_at(args) ? [true, "Pokemon borrado."] : [false, "Pokemon no encontrado."]
  rescue Exception
    return [false, "Error borrando Pokemon: " + $!.message.to_s]
  end

  def self.apply_pokemon_clone(args)
    pokemon = locate_pokemon(args)
    return [false, "Pokemon no encontrado."] if !pokemon
    copy = clone_pokemon(pokemon)
    return [false, "No se pudo clonar el Pokemon."] if !copy
    return place_pokemon(args, copy)
  rescue Exception
    return [false, "Error clonando Pokemon: " + $!.message.to_s]
  end

  def self.destination_args(args)
    return {
      "loc" => args["destLoc"].to_s,
      "index" => args["destIndex"].to_i,
      "box" => args["destBox"].to_i,
      "slot" => args["destSlot"].to_i
    }
  rescue Exception
    return {}
  end

  def self.apply_pokemon_place_edited(args)
    pokemon = locate_pokemon(args)
    if source_key(args) != "" && source_key(args) == destination_key(args)
      return [false, "Pokemon no encontrado."] if !pokemon
      apply_pokemon_fields(pokemon, args)
      return [true, "Pokemon actualizado."]
    end
    copy = nil
    if pokemon
      copy = clone_pokemon(pokemon)
      return [false, "No se pudo clonar el Pokemon editado."] if !copy
    else
      species = clamp(args["species"], 1, max_const_value("PBSpecies", 9999))
      level = clamp(args["level"], 1, defined?(PBExperience) ? PBExperience::MAXLEVEL : 100)
      return [false, "Especie invalida."] if species <= 0
      copy = PokeBattle_Pokemon.new(species, level, $Trainer)
    end
    apply_pokemon_fields(copy, args)
    args["replace"] = true if !args.has_key?("replace")
    return place_pokemon(args, copy)
  rescue Exception
    return [false, "Error colocando Pokemon editado: " + $!.message.to_s]
  end

  def self.apply_pokemon_swap(args)
    source = locate_pokemon(args)
    target_args = destination_args(args)
    target = locate_pokemon(target_args)
    return [false, "Pokemon origen no encontrado."] if !source
    return [false, "Pokemon destino no encontrado."] if !target
    src_loc = args["loc"].to_s
    dst_loc = args["destLoc"].to_s
    if src_loc == "party" && dst_loc == "party"
      src = args["index"].to_i
      dst = args["destIndex"].to_i
      return [false, "Indice de equipo invalido."] if !$Trainer || !$Trainer.party || src < 0 || dst < 0 || src >= $Trainer.party.length || dst >= $Trainer.party.length
      $Trainer.party[src], $Trainer.party[dst] = $Trainer.party[dst], $Trainer.party[src]
      return [true, "Pokemon intercambiados en el equipo."]
    elsif src_loc == "box" && dst_loc == "box"
      src_box = args["box"].to_i
      src_slot = args["slot"].to_i
      dst_box = args["destBox"].to_i
      dst_slot = args["destSlot"].to_i
      return [false, "PC no disponible."] if !defined?($PokemonStorage) || !$PokemonStorage
      return [false, "Caja invalida."] if src_box < 0 || src_box >= $PokemonStorage.maxBoxes || dst_box < 0 || dst_box >= $PokemonStorage.maxBoxes
      return [false, "Slot invalido."] if src_slot < 0 || src_slot >= $PokemonStorage.maxPokemon(src_box) || dst_slot < 0 || dst_slot >= $PokemonStorage.maxPokemon(dst_box)
      $PokemonStorage[src_box, src_slot], $PokemonStorage[dst_box, dst_slot] = $PokemonStorage[dst_box, dst_slot], $PokemonStorage[src_box, src_slot]
      return [true, "Pokemon intercambiados en el PC."]
    elsif src_loc == "party" && dst_loc == "box"
      src = args["index"].to_i
      dst_box = args["destBox"].to_i
      dst_slot = args["destSlot"].to_i
      return [false, "Equipo o PC no disponible."] if !$Trainer || !$Trainer.party || !defined?($PokemonStorage) || !$PokemonStorage
      return [false, "Indice de equipo invalido."] if src < 0 || src >= $Trainer.party.length
      return [false, "Caja invalida."] if dst_box < 0 || dst_box >= $PokemonStorage.maxBoxes
      return [false, "Slot invalido."] if dst_slot < 0 || dst_slot >= $PokemonStorage.maxPokemon(dst_box)
      $Trainer.party[src], $PokemonStorage[dst_box, dst_slot] = $PokemonStorage[dst_box, dst_slot], $Trainer.party[src]
      $Trainer.party.compact!
      return [true, "Pokemon intercambiados entre equipo y PC."]
    elsif src_loc == "box" && dst_loc == "party"
      src_box = args["box"].to_i
      src_slot = args["slot"].to_i
      dst = args["destIndex"].to_i
      return [false, "Equipo o PC no disponible."] if !$Trainer || !$Trainer.party || !defined?($PokemonStorage) || !$PokemonStorage
      return [false, "Caja invalida."] if src_box < 0 || src_box >= $PokemonStorage.maxBoxes
      return [false, "Slot invalido."] if src_slot < 0 || src_slot >= $PokemonStorage.maxPokemon(src_box)
      return [false, "Indice de equipo invalido."] if dst < 0 || dst >= $Trainer.party.length
      $PokemonStorage[src_box, src_slot], $Trainer.party[dst] = $Trainer.party[dst], $PokemonStorage[src_box, src_slot]
      $Trainer.party.compact!
      return [true, "Pokemon intercambiados entre PC y equipo."]
    end
    return [false, "Intercambio invalido."]
  rescue Exception
    return [false, "Error intercambiando Pokemon: " + $!.message.to_s]
  end

  def self.apply_pokemon_move(args)
    pokemon = locate_pokemon(args)
    return [false, "Pokemon no encontrado."] if !pokemon
    return [true, "Pokemon ya estaba en ese destino."] if source_key(args) != "" && source_key(args) == destination_key(args)
    if args["loc"].to_s == "party" && args["destLoc"].to_s == "party" && args.has_key?("destIndex")
      src = args["index"].to_i
      dst = args["destIndex"].to_i
      return [false, "Indice de equipo invalido."] if !$Trainer || !$Trainer.party || src < 0 || src >= $Trainer.party.length || dst < 0 || dst >= 6
      pokemon = $Trainer.party.delete_at(src)
      if bool_value(args["replace"]) && dst < $Trainer.party.length
        $Trainer.party[dst] = pokemon
      elsif dst >= $Trainer.party.length
        $Trainer.party.push(pokemon)
      else
        $Trainer.party.insert(dst, pokemon)
      end
      $Trainer.party.compact!
      return [true, "Pokemon movido dentro del equipo."]
    end
    ok, message = place_pokemon(args, pokemon)
    return [ok, message] if !ok
    delete_pokemon_at(args)
    return [true, "Pokemon movido."]
  rescue Exception
    return [false, "Error moviendo Pokemon: " + $!.message.to_s]
  end

  def self.each_pokemon_for_scope(scope, box_index = -1)
    count = 0
    if (scope == "party" || scope == "all") && $Trainer && $Trainer.party
      $Trainer.party.each do |pokemon|
        next if !pokemon
        yield pokemon
        count += 1
      end
    end
    if (scope == "box" || scope == "pc" || scope == "all") && defined?($PokemonStorage) && $PokemonStorage
      start_box = 0
      end_box = $PokemonStorage.maxBoxes - 1
      if scope == "box"
        box_index = $PokemonStorage.currentBox.to_i if box_index < 0
        start_box = box_index
        end_box = box_index
      end
      for box in start_box..end_box
        next if box < 0 || box >= $PokemonStorage.maxBoxes
        for slot in 0...$PokemonStorage.maxPokemon(box)
          pokemon = $PokemonStorage[box, slot]
          next if !pokemon
          yield pokemon
          count += 1
        end
      end
    end
    return count
  rescue Exception
    return count
  end

  def self.apply_pokemon_batch(args)
    scope = args["scope"].to_s
    scope = "party" if scope == ""
    box = args["box"].to_i
    field_args = {}
    field_args["level"] = args["level"] if bool_value(args["setLevel"])
    field_args["item"] = args["item"] if bool_value(args["setItem"])
    field_args["happiness"] = args["happiness"] if bool_value(args["setHappiness"])
    field_args["shiny"] = args["shiny"] if args.has_key?("shiny") && args["shiny"].to_s != "keep"
    count = 0
    each_pokemon_for_scope(scope, box) do |pokemon|
      apply_pokemon_fields(pokemon, field_args) if field_args.length > 0
      if bool_value(args["heal"])
        pokemon.heal if pokemon.respond_to?(:heal)
      end
      count += 1
    end
    return [true, "Lote aplicado a " + count.to_s + " Pokemon."]
  rescue Exception
    return [false, "Error lote Pokemon: " + $!.message.to_s]
  end

  def self.apply_give_item(args)
    return [false, "Mochila no disponible."] if !$PokemonBag
    id = item_id(args["item"])
    qty = clamp(args["qty"], 1, defined?(BAGMAXPERSLOT) ? BAGMAXPERSLOT : 999)
    return [false, "Objeto invalido."] if id <= 0
    return [$PokemonBag.pbStoreItem(id, qty), "Objeto entregado."]
  rescue Exception
    return [false, "Error objeto: " + $!.message.to_s]
  end

  def self.apply_set_item_qty(args)
    return [false, "Mochila no disponible."] if !$PokemonBag
    id = item_id(args["item"])
    qty = clamp(args["qty"], 0, defined?(BAGMAXPERSLOT) ? BAGMAXPERSLOT : 999)
    return [false, "Objeto invalido."] if id <= 0
    current = $PokemonBag.pbQuantity(id)
    if qty > current
      $PokemonBag.pbStoreItem(id, qty - current)
    elsif qty < current
      $PokemonBag.pbDeleteItem(id, current - qty)
    end
    return [true, "Cantidad de objeto actualizada."]
  rescue Exception
    return [false, "Error mochila: " + $!.message.to_s]
  end

  def self.apply_switch(args)
    return [false, "Switches no disponibles."] if !$game_switches
    id = args["id"].to_i
    return [false, "Switch invalido."] if id <= 0
    $game_switches[id] = bool_value(args["value"])
    $game_map.need_refresh = true if $game_map
    return [true, "Switch actualizado."]
  rescue Exception
    return [false, "Error switch: " + $!.message.to_s]
  end

  def self.apply_variable(args)
    return [false, "Variables no disponibles."] if !$game_variables
    id = args["id"].to_i
    return [false, "Variable invalida."] if id <= 0
    value = args["value"].to_s
    $game_variables[id] = (value =~ /\A-?\d+\z/) ? value.to_i : value
    $game_map.need_refresh = true if $game_map
    return [true, "Variable actualizada."]
  rescue Exception
    return [false, "Error variable: " + $!.message.to_s]
  end

  def self.apply_box(args)
    return [false, "PC no disponible."] if !defined?($PokemonStorage) || !$PokemonStorage
    box = args["box"].to_i
    return [false, "Caja invalida."] if box < 0 || box >= $PokemonStorage.maxBoxes
    $PokemonStorage[box].name = args["name"].to_s if args.has_key?("name")
    $PokemonStorage.currentBox = box if bool_value(args["makeCurrent"])
    return [true, "Caja actualizada."]
  rescue Exception
    return [false, "Error caja: " + $!.message.to_s]
  end

  def self.apply_pokedex(args)
    return [false, "Entrenador no disponible."] if !$Trainer
    max = max_const_value("PBSpecies", 0)
    return [false, "Pokedex no disponible."] if max <= 0
    species = args["species"].to_i
    owned = bool_value(args["owned"])
    seen = bool_value(args["seen"]) || owned
    if bool_value(args["all"])
      for i in 1..max
        $Trainer.setSeen(i) if seen
        $Trainer.setOwned(i) if owned
      end
      return [true, owned ? "Pokedex completada como capturada." : "Pokedex completada como vista."]
    end
    return [false, "Especie invalida."] if species <= 0 || species > max
    $Trainer.setSeen(species) if seen
    $Trainer.setOwned(species) if owned
    return [true, "Pokedex actualizada."]
  rescue Exception
    return [false, "Error Pokedex: " + $!.message.to_s]
  end

  def self.apply_achievement(args)
    return [false, "Logros no disponibles."] if !defined?(LOGROS) || !$PokemonGlobal
    index = args["index"].to_i
    return [false, "Logro invalido."] if index < 0 || index >= LOGROS.length
    min_status = defined?(LOGRO_OCULTO) ? LOGRO_OCULTO : 1
    max_status = defined?(LOGRO_COMPLETADO) ? LOGRO_COMPLETADO : 3
    status = clamp(args["status"], min_status, max_status)
    $PokemonGlobal.loadLogros if $PokemonGlobal.respond_to?(:loadLogros)
    if $PokemonGlobal.respond_to?(:logros) && $PokemonGlobal.logros
      $PokemonGlobal.logros[index] = status
      return [true, "Logro actualizado."]
    end
    return [false, "Lista de logros no disponible."]
  rescue Exception
    return [false, "Error logro: " + $!.message.to_s]
  end

  def self.live_mutating_command?(command_name)
    case command_name.to_s
    when "trainer_set", "pokemon_set", "pokemon_create", "pokemon_delete",
         "pokemon_clone", "pokemon_place_edited", "pokemon_swap",
         "pokemon_move", "pokemon_batch", "give_item", "set_item_qty",
         "heal_party", "switch_set", "variable_set", "box_set",
         "pokedex_set", "achievement_set"
      return true
    end
    return false
  rescue Exception
    return false
  end

  def self.refresh_summary_scene
    scene = @current_summary_scene
    return false if !scene
    party = scene.instance_variable_get("@party") rescue nil
    return false if !party || party.length <= 0
    index = scene.instance_variable_get("@partyindex") rescue 0
    index = index.to_i
    index = 0 if index < 0
    index = party.length - 1 if index >= party.length
    pokemon = party[index]
    return false if !pokemon
    scene.instance_variable_set("@partyindex", index)
    scene.instance_variable_set("@pokemon", pokemon)
    sprites = scene.instance_variable_get("@sprites") rescue nil
    if sprites && sprites["pokemon"]
      begin
        sprites["pokemon"].setPokemonBitmap(pokemon)
        sprites["pokemon"].color = Color.new(0, 0, 0, 0)
        pbPositionPokemonSprite(sprites["pokemon"], 40, 144)
      rescue Exception
      end
    end
    page = scene.instance_variable_get("@page") rescue 0
    page = page.to_i
    if page == 0
      if pokemon.respond_to?("isEgg?") && pokemon.isEgg? && scene.respond_to?("drawPageOneEgg")
        scene.drawPageOneEgg(pokemon)
      elsif scene.respond_to?("drawPageOne")
        scene.drawPageOne(pokemon)
      end
    elsif page == 1 && scene.respond_to?("drawPageTwo")
      scene.drawPageTwo(pokemon)
    elsif page == 2 && scene.respond_to?("drawPageThree")
      scene.drawPageThree(pokemon)
    elsif page == 3 && scene.respond_to?("drawPageFour")
      scene.drawPageFour(pokemon)
    elsif page == 4 && scene.respond_to?("drawPageFive")
      scene.drawPageFive(pokemon)
    end
    scene.pbUpdate if scene.respond_to?("pbUpdate")
    return true
  rescue Exception
    return false
  end

  def self.refresh_live_game_after_edit
    begin
      if $Trainer && $Trainer.party
        $Trainer.party.each { |pokemon| pokemon.calcStats if pokemon && pokemon.respond_to?("calcStats") }
      end
    rescue Exception
    end
    begin
      if $PokemonTemp && $PokemonTemp.respond_to?("dependentEvents") &&
         $PokemonTemp.dependentEvents && $PokemonTemp.dependentEvents.respond_to?("refresh_sprite")
        $PokemonTemp.dependentEvents.refresh_sprite(false)
      end
    rescue Exception
    end
    begin
      if defined?(SebiControls)
        scene = SebiControls.instance_variable_get("@party_level_scene") rescue nil
        scene.pbRefresh if scene && scene.respond_to?("pbRefresh")
        storage_scene = SebiControls.instance_variable_get("@storage_level_scene") rescue nil
        storage_scene.pbRefresh if storage_scene && storage_scene.respond_to?("pbRefresh")
      end
    rescue Exception
    end
    refresh_summary_scene
    begin
      if defined?(SebiLinkHub)
        battle_scene = SebiLinkHub.instance_variable_get("@battle_scene") rescue nil
        battle_scene.pbRefresh if battle_scene && battle_scene.respond_to?("pbRefresh")
      end
    rescue Exception
    end
    begin
      pbRefreshSceneMap if defined?(pbRefreshSceneMap)
    rescue Exception
    end
  rescue Exception
  end

  def self.apply_command(command)
    return [false, "Comando invalido."] if !command
    if command["cmd"].to_s == "close_window"
      @active = false
      @last_snapshot_frame = -9999
      clear_external_edit
      return [true, "SebiHeX cerrado."]
    end
    if external_editing?
      return save_external_edit_file if command["cmd"].to_s == "save_game"
      result = with_external_sections { apply_command_live(command) }
      return result || [false, "No se pudo aplicar el comando al archivo seleccionado."]
    end
    return apply_command_live(command)
  rescue Exception
    return [false, "Error comando: " + $!.message.to_s]
  end

  def self.save_external_edit_file
    return [false, "No hay archivo seleccionado para guardar."] if !external_editing?
    path = @external_edit_path.to_s
    sections = @external_edit_sections || {}
    return [false, "No hay archivo seleccionado para guardar."] if path == ""
    tmp = path + ".tmp"
    begin; File.delete(tmp) if FileTest.exist?(tmp); rescue Exception; end
    global = sections["global"]
    old_safesave = nil
    had_safesave = false
    begin
      trainer = sections["trainer"]
      trainer.metaID = global.playerID if trainer && global
    rescue Exception
    end
    begin
      game_system = sections["gameSystem"]
      if game_system && defined?($data_system)
        if $data_system.respond_to?("magic_number")
          game_system.magic_number = $data_system.magic_number
        else
          game_system.magic_number = $data_system.version_id
        end
      end
    rescue Exception
    end
    begin
      if global && global.respond_to?(:safesave)
        had_safesave = true
        old_safesave = global.safesave
        global.safesave = false
      end
    rescue Exception
    end
    File.open(tmp, "wb") do |file|
      Marshal.dump(sections["trainer"], file)
      Marshal.dump(sections["frame"] || (Graphics.frame_count rescue 0), file)
      Marshal.dump(sections["gameSystem"], file)
      Marshal.dump(sections["pokemonSystem"], file)
      Marshal.dump(sections["mapId"].to_i, file)
      Marshal.dump(sections["switches"], file)
      Marshal.dump(sections["variables"], file)
      Marshal.dump(sections["selfSwitches"], file)
      Marshal.dump(sections["screen"], file)
      Marshal.dump(sections["mapFactory"], file)
      Marshal.dump(sections["player"], file)
      Marshal.dump(sections["global"], file)
      Marshal.dump(sections["pokemonMap"], file)
      Marshal.dump(sections["bag"], file)
      Marshal.dump(sections["storage"], file)
    end
    begin
      global.safesave = old_safesave if had_safesave && global
    rescue Exception
    end
    begin; File.delete(path) if FileTest.exist?(path); rescue Exception; end
    File.rename(tmp, path)
    SebiAutoBackups.write_preview_json(path) if defined?(SebiAutoBackups)
    return [true, "Partida guardada en " + File.basename(path).to_s + "."]
  rescue Exception
    begin
      global.safesave = old_safesave if had_safesave && global
    rescue Exception
    end
    begin; File.delete(tmp) if tmp && FileTest.exist?(tmp); rescue Exception; end
    return [false, "No se pudo guardar el archivo seleccionado: " + $!.message.to_s]
  end

  def self.apply_command_live(command)
    return [false, "Comando invalido."] if !command
    args = command["args"] || {}
    case command["cmd"].to_s
    when "trainer_set"
      return apply_trainer(args)
    when "pokemon_set"
      return apply_pokemon(args)
    when "pokemon_create"
      return apply_pokemon_create(args)
    when "pokemon_delete"
      return apply_pokemon_delete(args)
    when "pokemon_clone"
      return apply_pokemon_clone(args)
    when "pokemon_place_edited"
      return apply_pokemon_place_edited(args)
    when "pokemon_swap"
      return apply_pokemon_swap(args)
    when "pokemon_move"
      return apply_pokemon_move(args)
    when "pokemon_batch"
      return apply_pokemon_batch(args)
    when "give_item"
      return apply_give_item(args)
    when "set_item_qty"
      return apply_set_item_qty(args)
    when "heal_party"
      if $Trainer && $Trainer.party
        $Trainer.party.each { |pokemon| pokemon.heal if pokemon }
        return [true, "Equipo curado."]
      end
      return [false, "No hay equipo."]
    when "switch_set"
      return apply_switch(args)
    when "variable_set"
      return apply_variable(args)
    when "box_set"
      return apply_box(args)
    when "pokedex_set"
      return apply_pokedex(args)
    when "achievement_set"
      return apply_achievement(args)
    when "save_game"
      ok = defined?(pbSave) && pbSave(false)
      if ok && defined?(SebiAutoBackups)
        current_path = SebiAutoBackups.save_path
        target = current_edit_target
        if target && target != "" && target.gsub("\\", "/") != current_path.gsub("\\", "/")
          SebiAutoBackups.copy_file(current_path, target)
        end
      end
      return [ok, "Guardado solicitado."]
    else
      return [false, "Comando desconocido: " + command["cmd"].to_s]
    end
  rescue Exception
    return [false, "Error comando: " + $!.message.to_s]
  end

  def self.write_result(seq, ok, message)
    atomic_write(result_path, json({
      "seq" => seq.to_s,
      "ok" => ok ? true : false,
      "message" => message.to_s,
      "frame" => safe(0) { Graphics.frame_count.to_i },
      "time" => Time.now.to_s
    }))
  rescue Exception
  end

  def self.process_commands
    path = command_path
    return if !FileTest.exist?(path)
    text = ""
    File.open(path, "rb") { |file| text = file.read }
    return if !text || text == ""
    File.open(path, "wb") { |file| file.write("") }
    live_changed = false
    text.each_line do |line|
      command = parse_command(line)
      next if !command || command["cmd"].to_s == ""
      live_command = !external_editing? && live_mutating_command?(command["cmd"])
      ok, message = apply_command(command)
      live_changed = true if ok && live_command
      write_result(command["seq"], ok, message)
    end
    refresh_live_game_after_edit if live_changed
    write_state_file(true)
  rescue Exception
    write_result("error", false, "Error leyendo comandos: " + $!.message.to_s)
  end

  def self.command_file_pending?
    path = command_path
    return false if !FileTest.exist?(path)
    return (File.size(path) rescue 0) > 0
  rescue Exception
    return false
  end

  def self.clear_edit_target
    begin; File.delete(edit_target_path) if FileTest.exist?(edit_target_path); rescue Exception; end
  end

  def self.current_edit_target
    return "" if !FileTest.exist?(edit_target_path)
    text = ""
    File.open(edit_target_path, "rb") { |file| text = file.read.to_s }
    return text.gsub(/\r|\n/, "")
  rescue Exception
    return ""
  end

  def self.open_external_file(path)
    return [false, _INTL("SebiHeX no esta disponible.")] if path.to_s == ""
    return [false, _INTL("No se encontro la partida elegida.")] if !defined?(SebiAutoBackups) || !SebiAutoBackups.file_exists?(path)
    sections = SebiAutoBackups.load_save_sections(path)
    return [false, _INTL("Esa partida parece corrupta o incompatible.")] if !sections
    editor = editor_path
    return [false, _INTL("No se encontro el editor de partida.")] if !FileTest.exist?(editor)
    @external_edit_path = path.to_s
    @external_edit_sections = sections
    mark_window_opening
    @active = true
    ensure_runtime
    atomic_write(edit_target_path, path.to_s)
    delete_runtime_file(open_after_load_path)
    delete_runtime_file(command_path)
    delete_runtime_file(result_path)
    write_data_file if !@data_written && !data_file_ready?
    @data_written = true if data_file_ready?
    write_state_file(true)
    if !open_path(editor)
      @active = false
      clear_external_edit
      return [false, _INTL("No se pudo abrir el editor de partida.")]
    end
    @last_open_frame = Graphics.frame_count rescue 0
    return [true, _INTL("SebiHeX abierto para editar {1}.", File.basename(path.to_s))]
  rescue Exception
    clear_external_edit
    return [false, _INTL("No se pudo abrir esa partida en SebiHeX.")]
  end

  def self.open_editor(clear_target = true)
    if clear_target
      clear_external_edit
      clear_edit_target
    end
    path = editor_path
    if !FileTest.exist?(path)
      Kernel.pbMessage(_INTL("No se encontro el editor de partida."))
      return
    end
    mark_window_opening
    @active = true
    write_data_file if !@data_written && !data_file_ready?
    @data_written = true if data_file_ready?
    write_state_file(true)
    if !open_path(path)
      @active = false
      Kernel.pbMessage(_INTL("No se pudo abrir el editor de partida."))
      return
    end
    @last_open_frame = Graphics.frame_count rescue 0
  end

  def self.request_open_after_load(path = "")
    ensure_runtime
    atomic_write(open_after_load_path, path.to_s)
    atomic_write(edit_target_path, path.to_s)
    return true
  rescue Exception
    return false
  end

  def self.handle_open_after_load
    path = open_after_load_path
    return if !FileTest.exist?(path)
    return if !$Trainer || !$game_map || !$game_player
    if $game_temp
      return if $game_temp.in_battle
      return if $game_temp.battle_calling
      return if $game_temp.message_window_showing
      return if $game_temp.player_transferring
    end
    begin
      return if pbMapInterpreterRunning?
    rescue Exception
    end
    begin; File.delete(path); rescue Exception; end
    open_editor(false)
  rescue Exception
  end

  def self.handle_shortcut
    return if !defined?(Input) || !Input.respond_to?(:triggerex?)
    return if !Input.triggerex?(EDITOR_KEY)
    frame = Graphics.frame_count rescue 0
    return if @last_open_frame && frame - @last_open_frame < COOLDOWN_FRAMES
    open_editor
  rescue Exception
  end

  def self.update
    handle_open_after_load
    if !@active
      return if !command_file_pending?
      return if !window_alive?
      @active = true
    end
    write_data_file if !@data_written
    process_commands
    if !window_alive?
      @active = false
      clear_external_edit
      return
    end
    write_state_file(false)
  rescue Exception
  end
end

module SebiPartyQuickActions
  @current_screen = nil

  def self.current_screen=(screen)
    @current_screen = screen
  end

  def self.current_screen
    return @current_screen
  end

  def self.party_action_menu?(commands)
    return false if !commands
    labels = []
    for command in commands
      labels.push(command.to_s)
    end
    return labels.include?("Pokedex") && labels.include?("Salir") &&
           (labels.include?("Mover") || labels.include?("Datos") || labels.include?("Soltar"))
  end

  def self.party_from_scene(scene)
    return nil if !scene
    return scene.instance_variable_get("@party")
  rescue Exception
    return nil
  end

  def self.active_index(scene)
    return -1 if !scene
    return scene.instance_variable_get("@activecmd").to_i
  rescue Exception
    return -1
  end

  def self.party_label(index, pokemon)
    mark = pokemon.isShiny? ? " *" : ""
    return (index + 1).to_s + ". " + pokemon.name.to_s + " Nv." + pokemon.level.to_s + mark
  end

  def self.choose_index(scene, party, message, shiny_state = nil, exclude_index = nil)
    commands = []
    indexes = []
    for i in 0...party.length
      pokemon = party[i]
      next if !pokemon || pokemon.isEgg?
      next if exclude_index != nil && i == exclude_index
      next if shiny_state == true && !pokemon.isShiny?
      next if shiny_state == false && pokemon.isShiny?
      indexes.push(i)
      commands.push(party_label(i, pokemon))
    end
    if indexes.length == 0
      scene.pbDisplay(_INTL("No hay ningun Pokemon valido para elegir."))
      return nil
    end
    commands.push(_INTL("Cancelar"))
    cmd = scene.pbShowCommands(message, commands, commands.length - 1)
    return nil if cmd < 0 || cmd >= indexes.length
    return indexes[cmd]
  end

  def self.move_shiny_for(scene, index)
    party = party_from_scene(scene)
    return if !party || index < 0 || index >= party.length
    pokemon = party[index]
    return if !pokemon || pokemon.isEgg?
    active_ref = { "loc" => "party", "index" => index, "box" => -1, "slot" => -1, "pokemon" => pokemon }
    if pokemon.isShiny?
      source_ref = active_ref
      target_ref = SebiCheats.choose_pokemon_ref_for_shiny(_INTL("Elige quien recibira el shiny de {1}.", pokemon.name), false, source_ref)
    else
      target_ref = active_ref
      source_ref = SebiCheats.choose_pokemon_ref_for_shiny(_INTL("Elige el Pokemon shiny que cedera el shiny a {1}.", pokemon.name), true, target_ref)
    end
    return if source_ref == nil || target_ref == nil
    source = source_ref["pokemon"]
    target = target_ref["pokemon"]
    return if !source || !target
    if !scene.pbDisplayConfirm(_INTL("Mover el shiny de {1} a {2}?", source.name, target.name))
      return
    end
    SebiCheats.set_shiny(source, false)
    SebiCheats.set_shiny(target, true)
    pbSeenForm(target) if defined?(pbSeenForm)
    scene.pbRefresh
    scene.pbDisplay(_INTL("{1} ya no es shiny. {2} ahora es shiny.", source.name, target.name))
  rescue Exception
    scene.pbDisplay(_INTL("No se pudo mover el shiny.")) if scene
  end

  def self.raise_to_strongest_for(scene, index)
    party = party_from_scene(scene)
    return if !party || index < 0 || index >= party.length
    pokemon = party[index]
    return if !pokemon || pokemon.isEgg?
    highest = SebiCheats.highest_party_level
    target = [highest, SebiCheats.current_level_cap].min
    if target <= 0
      scene.pbDisplay(_INTL("No hay Pokemon validos para comparar."))
      return
    end
    if pokemon.level >= target
      scene.pbDisplay(_INTL("{1} ya esta al nivel {2}.", pokemon.name, target))
      return
    end
    result = SebiCheats.raise_pokemon_to_level(pokemon, target, { "loc" => "party", "index" => index, "box" => -1, "slot" => -1 })
    if result
      scene.pbRefreshSingle(index)
      scene.pbDisplay(_INTL("{1} subio al nivel {2}.", pokemon.name, target))
      SebiCheats.offer_level_review([result]) if SebiCheats.respond_to?(:offer_level_review)
    else
      scene.pbDisplay(_INTL("No se pudo subir el nivel de {1}.", pokemon.name))
    end
  rescue Exception
    scene.pbDisplay(_INTL("No se pudo igualar el nivel.")) if scene
  end

  def self.view_db_for(scene, index)
    party = party_from_scene(scene)
    return if !party || index < 0 || index >= party.length
    pokemon = party[index]
    return if !pokemon || pokemon.isEgg?
    SebiPokemonDB.open_pokemon(pokemon) if defined?(SebiPokemonDB)
  rescue Exception
    scene.pbDisplay(_INTL("No se pudo abrir la DB.")) if scene
  end
end

class PokemonScreen
  unless method_defined?(:sebi_party_actions_pbPokemonScreen_without_quick_actions)
    alias sebi_party_actions_pbPokemonScreen_without_quick_actions pbPokemonScreen

    def pbPokemonScreen
      SebiPartyQuickActions.current_screen = self
      return sebi_party_actions_pbPokemonScreen_without_quick_actions
    ensure
      SebiPartyQuickActions.current_screen = nil
    end
  end
end

class PokemonScreen_Scene
  unless method_defined?(:sebi_controls_pbStartScene_without_f4_level_shortcut)
    alias sebi_controls_pbStartScene_without_f4_level_shortcut pbStartScene

    def pbStartScene(*args)
      SebiControls.party_level_scene = self if defined?(SebiControls)
      return sebi_controls_pbStartScene_without_f4_level_shortcut(*args)
    end
  end

  unless method_defined?(:sebi_controls_pbEndScene_without_f4_level_shortcut)
    alias sebi_controls_pbEndScene_without_f4_level_shortcut pbEndScene

    def pbEndScene
      return sebi_controls_pbEndScene_without_f4_level_shortcut
    ensure
      SebiControls.party_level_scene = nil if defined?(SebiControls)
    end
  end

  unless method_defined?(:sebi_party_actions_pbShowCommands_without_quick_actions)
    alias sebi_party_actions_pbShowCommands_without_quick_actions pbShowCommands

    def pbShowCommands(helptext, commands, index = 0)
      if SebiPartyQuickActions.current_screen && SebiPartyQuickActions.party_action_menu?(commands)
        original_exit = commands.length - 1
        extended = commands.clone
        insert_at = extended.length - 1
        cmd_shiny = insert_at
        extended.insert(insert_at, _INTL("Mover shiny"))
        cmd_level = insert_at + 1
        extended.insert(insert_at + 1, _INTL("Igualar nivel"))
        cmd_db = insert_at + 2
        extended.insert(insert_at + 2, _INTL("Ver en PokemonDB"))
        command = sebi_party_actions_pbShowCommands_without_quick_actions(helptext, extended, index)
        if command == cmd_shiny
          SebiPartyQuickActions.move_shiny_for(self, SebiPartyQuickActions.active_index(self))
          return original_exit
        elsif command == cmd_level
          SebiPartyQuickActions.raise_to_strongest_for(self, SebiPartyQuickActions.active_index(self))
          return original_exit
        elsif command == cmd_db
          SebiPartyQuickActions.view_db_for(self, SebiPartyQuickActions.active_index(self))
          return original_exit
        end
        return command
      elsif defined?(SebiPokemonDB) && commands && commands.include?(_INTL("Datos")) && commands.include?(_INTL("Salir"))
        original_exit = commands.length - 1
        extended = commands.clone
        insert_at = extended.length - 1
        cmd_db = insert_at
        extended.insert(insert_at, _INTL("Ver en PokemonDB"))
        command = sebi_party_actions_pbShowCommands_without_quick_actions(helptext, extended, index)
        if command == cmd_db
          SebiPartyQuickActions.view_db_for(self, SebiPartyQuickActions.active_index(self))
          return original_exit
        end
        return command
      end
      return sebi_party_actions_pbShowCommands_without_quick_actions(helptext, commands, index)
    end
  end
end

class PokemonScreen_Scene
  unless method_defined?(:sebi_db_update_without_hotkey)
    alias sebi_db_update_without_hotkey update

    def update
      db_pressed = defined?(SebiControls) ? SebiControls.db_trigger? : Input.trigger?(Input::F3)
      if defined?(SebiPokemonDB) && db_pressed &&
         (!$game_temp || !$game_temp.in_battle) &&
         SebiPokemonDB.can_open_hotkey?
        party = instance_variable_get("@party") rescue nil
        SebiPokemonDB.open_team(party) if party
      end
      sebi_db_update_without_hotkey
    end
  end
end

if defined?(PokemonStorageScene)
  class PokemonStorageScene
    unless method_defined?(:sebi_controls_pbStartBox_without_f4_level_shortcut)
      alias sebi_controls_pbStartBox_without_f4_level_shortcut pbStartBox

      def pbStartBox(screen, command)
        ret = sebi_controls_pbStartBox_without_f4_level_shortcut(screen, command)
        SebiControls.storage_level_scene = self if defined?(SebiControls)
        return ret
      end
    end

    unless method_defined?(:sebi_controls_pbCloseBox_without_f4_level_shortcut)
      alias sebi_controls_pbCloseBox_without_f4_level_shortcut pbCloseBox

      def pbCloseBox
        return sebi_controls_pbCloseBox_without_f4_level_shortcut
      ensure
        SebiControls.storage_level_scene = nil if defined?(SebiControls)
      end
    end

    unless method_defined?(:sebi_storage_pokedex_pbShowCommands_without_pokedex)
      alias sebi_storage_pokedex_pbShowCommands_without_pokedex pbShowCommands

      def sebi_storage_pokedex_menu?(commands)
        return false if !commands
        labels = []
        for command in commands
          labels.push(command.to_s)
        end
        return false if labels.include?("Pokedex")
        return labels.include?("Datos") && labels.include?("Marcar") && labels.include?("Salir")
      rescue Exception
        return false
      end

      def sebi_storage_pokemon_menu?(commands)
        return false if !commands
        labels = []
        for command in commands
          labels.push(command.to_s)
        end
        return labels.include?("Datos") && labels.include?("Salir") &&
               (labels.include?("Mover") || labels.include?("Sacar") ||
                labels.include?("Objeto") || labels.include?("Marcar") ||
                labels.include?("Soltar") || labels.include?("Pokedex"))
      rescue Exception
        return false
      end

      def sebi_storage_current_pokemon_ref
        return nil if !@storage
        held = @screen.pbHeldPokemon if @screen && @screen.respond_to?(:pbHeldPokemon)
        if held
          return { "loc" => "held", "index" => -1, "box" => -1, "slot" => -1, "pokemon" => held }
        end
        index = @selection.to_i
        return nil if index < 0
        if @command == 1 || @choseFromParty
          pokemon = (@storage.party && index < @storage.party.length) ? @storage.party[index] : nil
          return nil if !pokemon
          return { "loc" => "party", "index" => index, "box" => -1, "slot" => -1, "pokemon" => pokemon }
        else
          box = @storage.currentBox.to_i
          pokemon = @storage[box, index]
          return nil if !pokemon
          return { "loc" => "box", "index" => -1, "box" => box, "slot" => index, "pokemon" => pokemon }
        end
      rescue Exception
        return nil
      end

      def sebi_storage_pokedex_current_pokemon
        ref = sebi_storage_current_pokemon_ref
        return ref ? ref["pokemon"] : nil
      rescue Exception
        return nil
      end

      def sebi_storage_open_pokedex_for(pokemon)
        return false if !pokemon
        if defined?(AdvancedPokedexScene) && defined?(AdvancedPokedex)
          scene = AdvancedPokedexScene.new
          screen = AdvancedPokedex.new(scene)
          screen.pbStartScreen(pokemon.species, 2)
          return true
        end
        return false
      rescue Exception
        return false
      end

      def sebi_storage_confirm(message)
        return pbDisplayConfirm(message) if respond_to?(:pbDisplayConfirm)
        return Kernel.pbConfirmMessage(message) if Kernel.respond_to?(:pbConfirmMessage)
        return @screen.pbConfirm(message) if @screen && @screen.respond_to?(:pbConfirm)
        return true
      rescue Exception
        return false
      end

      def sebi_storage_move_shiny_for_current
        if !defined?(SebiCheats) || !SebiCheats.respond_to?(:choose_pokemon_ref_for_shiny)
          pbDisplay(_INTL("Mover shiny no esta disponible.")) if respond_to?(:pbDisplay)
          return false
        end
        active_ref = sebi_storage_current_pokemon_ref
        if active_ref == nil
          pbDisplay(_INTL("No hay ningun Pokemon seleccionado.")) if respond_to?(:pbDisplay)
          return false
        end
        pokemon = active_ref["pokemon"]
        if !pokemon || (pokemon.respond_to?(:isEgg?) && pokemon.isEgg?)
          pbDisplay(_INTL("No se puede mover shiny con este Pokemon.")) if respond_to?(:pbDisplay)
          return false
        end
        if pokemon.isShiny?
          source_ref = active_ref
          target_ref = SebiCheats.choose_pokemon_ref_for_shiny(_INTL("Elige quien recibira el shiny de {1}.", pokemon.name), false, source_ref)
        else
          target_ref = active_ref
          source_ref = SebiCheats.choose_pokemon_ref_for_shiny(_INTL("Elige el Pokemon shiny que cedera el shiny a {1}.", pokemon.name), true, target_ref)
        end
        return false if source_ref == nil || target_ref == nil
        source = source_ref["pokemon"]
        target = target_ref["pokemon"]
        return false if !source || !target
        return false if !sebi_storage_confirm(_INTL("Mover el shiny de {1} a {2}?", source.name, target.name))
        SebiCheats.set_shiny(source, false)
        SebiCheats.set_shiny(target, true)
        pbSeenForm(target) if defined?(pbSeenForm)
        if respond_to?(:pbHardRefresh)
          pbHardRefresh
        elsif respond_to?(:pbRefresh)
          pbRefresh
        end
        pbDisplay(_INTL("{1} ya no es shiny. {2} ahora es shiny.", source.name, target.name)) if respond_to?(:pbDisplay)
        return true
      rescue Exception
        pbDisplay(_INTL("No se pudo mover el shiny.")) if respond_to?(:pbDisplay)
        return false
      end

      def pbShowCommands(message, commands, index = 0)
        if sebi_storage_pokemon_menu?(commands)
          original_exit = commands.length - 1
          visible = []
          actions = []
          added_shiny = false
          added_pokedex = false
          needs_pokedex = sebi_storage_pokedex_menu?(commands)
          for i in 0...commands.length
            label = commands[i].to_s
            next if label == _INTL("Marcar")
            if i == original_exit
              if !added_shiny && !commands.include?(_INTL("Mover shiny"))
                visible.push(_INTL("Mover shiny"))
                actions.push("shiny")
                added_shiny = true
              end
              if needs_pokedex && !added_pokedex
                visible.push(_INTL("Pokedex"))
                actions.push("pokedex")
                added_pokedex = true
              end
            end
            visible.push(commands[i])
            actions.push(i)
          end
          command = sebi_storage_pokedex_pbShowCommands_without_pokedex(message, visible, [index, visible.length - 1].min)
          return command if command < 0 || command >= actions.length
          action = actions[command]
          if action == "shiny"
            sebi_storage_move_shiny_for_current
            return original_exit
          elsif action == "pokedex"
            pokemon = sebi_storage_pokedex_current_pokemon
            if !sebi_storage_open_pokedex_for(pokemon)
              pbDisplay(_INTL("No se pudo abrir la Pokedex de este Pokemon.")) if respond_to?(:pbDisplay)
            end
            return original_exit
          end
          return action.to_i
        end
        return sebi_storage_pokedex_pbShowCommands_without_pokedex(message, commands, index)
      end
    end
  end
end

if false # SebiDisplaySettings eliminado: Pantalla/Zoom ya no se define ni se ejecuta.
  DATA_IVAR = :@sebi_pokelink_display
  PRESETS = [
    ["Clasico 4:3", 512, 384, "vista original"],
    ["16:9 cerca", 640, 360, "menos alto, sin franjas 16:9"],
    ["16:9 normal", 768, 432, "mas mapa a los lados"],
    ["16:9 lejos", 896, 504, "mas campo de vision"],
    ["16:9 muy lejos", 1024, 576, "mucho campo de vision"],
    ["21:9 ultrawide", 1024, 432, "ideal para pantalla ancha"],
    ["21:9 ultrawide lejos", 1280, 540, "ultrawide con mas mapa"],
    ["32:9 extremo", 1536, 432, "muy panoramico"]
  ]

  @fallback_data = nil
  @last_applied = nil
  @auto_cache_key = nil
  @auto_cache_value = nil
  @loaded_file_config = false

  def self.data
    if !$PokemonGlobal
      @fallback_data = {} if !@fallback_data.is_a?(Hash)
      return normalize_data(@fallback_data)
    end
    value = $PokemonGlobal.instance_variable_get(DATA_IVAR)
    value = {} if !value.is_a?(Hash)
    $PokemonGlobal.instance_variable_set(DATA_IVAR, value)
    return normalize_data(value)
  rescue Exception
    @fallback_data = {} if !@fallback_data.is_a?(Hash)
    return normalize_data(@fallback_data)
  end

  def self.normalize_data(value)
    if !@loaded_file_config && defined?(SebiLinkFileConfig) && SebiLinkFileConfig.has_key?("display_width")
      value[:width] = SebiLinkFileConfig.get_int("display_width", 512)
    elsif value[:width] == nil
      value[:width] = 512
    end
    if !@loaded_file_config && defined?(SebiLinkFileConfig) && SebiLinkFileConfig.has_key?("display_height")
      value[:height] = SebiLinkFileConfig.get_int("display_height", 384)
    elsif value[:height] == nil
      value[:height] = 384
    end
    if !@loaded_file_config && defined?(SebiLinkFileConfig) && SebiLinkFileConfig.has_key?("display_preset")
      value[:preset] = SebiLinkFileConfig.get_int("display_preset", 0)
    elsif value[:preset] == nil
      value[:preset] = 0
    end
    if !@loaded_file_config && defined?(SebiLinkFileConfig) && SebiLinkFileConfig.has_key?("display_auto")
      value[:auto] = SebiLinkFileConfig.get_bool("display_auto", false)
    elsif value[:auto] == nil
      value[:auto] = false
    end
    value[:width] = clamp_dimension(value[:width], 320, 1920)
    value[:height] = clamp_dimension(value[:height], 240, 1080)
    @loaded_file_config = true
    return value
  end

  def self.clamp(value, min_value, max_value)
    value = value.to_i
    value = min_value if value < min_value
    value = max_value if value > max_value
    return value
  end

  def self.clamp_dimension(value, min_value, max_value)
    value = clamp(value, min_value, max_value)
    value = ((value + 8) / 16) * 16
    value = min_value if value < min_value
    value = max_value if value > max_value
    return value
  end

  def self.width
    return data[:width]
  end

  def self.height
    return data[:height]
  end

  def self.auto?
    return data[:auto] ? true : false
  end

  def self.save_config
    return if !defined?(SebiLinkFileConfig)
    SebiLinkFileConfig.set("display_width", data[:width].to_s)
    SebiLinkFileConfig.set("display_height", data[:height].to_s)
    SebiLinkFileConfig.set("display_preset", data[:preset] == nil ? "" : data[:preset].to_s)
    SebiLinkFileConfig.set("display_auto", data[:auto] ? "true" : "false")
  end

  def self.set_resolution(width, height, preset = nil)
    data[:auto] = false
    data[:width] = clamp_dimension(width, 320, 1920)
    data[:height] = clamp_dimension(height, 240, 1080)
    data[:preset] = preset
    save_config
    apply(true)
  end

  def self.set_auto_resolution
    data[:auto] = true
    @auto_cache_key = nil
    @auto_cache_value = nil
    save_config
    apply(true)
  end

  def self.current_preset_name
    return "Auto pantalla" if auto?
    for i in 0...PRESETS.length
      return PRESETS[i][0] if PRESETS[i][1] == width && PRESETS[i][2] == height
    end
    return "Personalizada"
  end

  def self.current_label
    return current_preset_name + " - " + width.to_s + "x" + height.to_s
  end

  def self.resize_supported?
    return Graphics.respond_to?(:resize_screen)
  rescue Exception
    return false
  end

  def self.window_client_size
    return nil if !defined?(Win32API)
    return nil if !defined?(pbFindRgssWindow)
    get_client_rect = Win32API.new("user32", "GetClientRect", "LP", "I")
    rect = "\0" * 16
    hwnd = pbFindRgssWindow
    return nil if !hwnd || hwnd == 0
    return nil if get_client_rect.call(hwnd, rect) == 0
    values = rect.unpack("l4")
    width = values[2] - values[0]
    height = values[3] - values[1]
    return [width, height] if width > 0 && height > 0
    return nil
  rescue Exception
    return nil
  end

  def self.screen_size
    client_size = window_client_size
    return client_size if client_size
    if defined?(Win32API)
      metrics = Win32API.new("user32", "GetSystemMetrics", "I", "I")
      screen_width = metrics.call(0)
      screen_height = metrics.call(1)
      return [screen_width, screen_height] if screen_width && screen_height && screen_width > 0 && screen_height > 0
    end
    return [1280, 720]
  rescue Exception
    return [1280, 720]
  end

  def self.auto_resolution
    screen_width, screen_height = screen_size
    aspect = screen_width.to_f / screen_height.to_f
    # Most Pokemon Z maps were authored for 4:3/16:9. Wider views can reveal
    # black staging areas that are intentionally outside the normal camera.
    aspect = [aspect, 16.0 / 9.0].min
    map_id = ($game_map && $game_map.respond_to?(:map_id)) ? $game_map.map_id : 0
    cache_key = [screen_width, screen_height, aspect, map_id]
    return @auto_cache_value if @auto_cache_key == cache_key && @auto_cache_value
    if aspect >= 1.70
      heights = [360, 344, 328, 312, 296, 280, 264, 248, 240]
    else
      heights = [384, 368, 352, 336, 320, 304, 288, 272, 256, 240]
    end
    best = nil
    best_blank = 999.0
    for h in heights
      w = clamp_dimension((h * aspect).round, 320, 1920)
      h2 = clamp_dimension(h, 240, 1080)
      blank = visible_blank_ratio(w, h2)
      if blank < best_blank
        best_blank = blank
        best = [w, h2]
      end
      if blank <= 0.06
        @auto_cache_key = cache_key
        @auto_cache_value = [w, h2]
        return @auto_cache_value
      end
    end
    best = [512, 384] if !best
    @auto_cache_key = cache_key
    @auto_cache_value = best
    return best
  end

  def self.visible_blank_ratio(test_width, test_height)
    return 0.0 if !$game_map || !$game_player
    data_table = $game_map.data
    return 0.0 if !data_table
    tile_width = defined?(Game_Map::TILEWIDTH) ? Game_Map::TILEWIDTH : 32
    tile_height = defined?(Game_Map::TILEHEIGHT) ? Game_Map::TILEHEIGHT : 32
    tiles_wide = (test_width.to_f / tile_width).ceil + 2
    tiles_high = (test_height.to_f / tile_height).ceil + 2
    left = $game_player.x - (tiles_wide / 2)
    top = $game_player.y - (tiles_high / 2)
    map_width = data_table.respond_to?(:xsize) ? data_table.xsize : $game_map.width
    map_height = data_table.respond_to?(:ysize) ? data_table.ysize : $game_map.height
    layers = data_table.respond_to?(:zsize) ? data_table.zsize : 3
    total = 0
    blanks = 0
    for y in top...(top + tiles_high)
      for x in left...(left + tiles_wide)
        total += 1
        if x < 0 || y < 0 || x >= map_width || y >= map_height
          blanks += 1
          next
        end
        filled = false
        for z in 0...layers
          tile_id = 0
          begin
            tile_id = data_table[x, y, z]
          rescue Exception
            tile_id = 0
          end
          if tile_id && tile_id.to_i > 0
            filled = true
            break
          end
        end
        blanks += 1 if !filled
      end
    end
    return 0.0 if total <= 0
    return blanks.to_f / total.to_f
  rescue Exception
    return 0.0
  end

  def self.target_resolution
    return auto_resolution if auto?
    return [width, height]
  end

  def self.set_graphics_size(width, height)
    begin
      Graphics.class_variable_set(:@@width, width)
      Graphics.class_variable_set(:@@height, height)
      return
    rescue Exception
    end
    begin
      Graphics.module_eval("@@width = " + width.to_i.to_s + "\n@@height = " + height.to_i.to_s)
    rescue Exception
    end
  end

  def self.apply(force = false)
    return false if !resize_supported?
    if force
      @auto_cache_key = nil
      @auto_cache_value = nil
    end
    target_width, target_height = target_resolution
    data[:width] = target_width
    data[:height] = target_height
    target = [target_width, target_height]
    return true if !force && @last_applied == target
    save_config
    set_graphics_size(target_width, target_height)
    Graphics.resize_screen(target_width, target_height)
    set_graphics_size(target_width, target_height)
    Graphics.frame_reset if Graphics.respond_to?(:frame_reset)
    if $game_player && $game_player.respond_to?(:center)
      $game_player.center($game_player.x, $game_player.y)
    end
    @last_applied = target
    return true
  rescue Exception
    @last_applied = nil
    Kernel.pbMessage(_INTL("No se pudo aplicar esta resolucion.")) if force
    return false
  end

  def self.choose_preset
    commands = []
    for preset in PRESETS
      commands.push(preset[0] + " - " + preset[1].to_s + "x" + preset[2].to_s)
    end
    commands.push(_INTL("Cancelar"))
    cmd = Kernel.pbMessage(_INTL("Elige campo de vision."), commands, commands.length)
    return if cmd < 0 || cmd >= PRESETS.length
    preset = PRESETS[cmd]
    set_resolution(preset[1], preset[2], cmd)
    Kernel.pbMessage(_INTL("Pantalla cambiada a {1}.", current_label))
  end

  def self.custom_resolution
    params = ChooseNumberParams.new
    params.setRange(320, 1920)
    params.setDefaultValue(width)
    params.setCancelValue(width)
    new_width = Kernel.pbMessageChooseNumber(_INTL("Ancho interno de pantalla."), params)
    params = ChooseNumberParams.new
    params.setRange(240, 1080)
    params.setDefaultValue(height)
    params.setCancelValue(height)
    new_height = Kernel.pbMessageChooseNumber(_INTL("Alto interno de pantalla."), params)
    new_width = clamp_dimension(new_width, 320, 1920)
    new_height = clamp_dimension(new_height, 240, 1080)
    set_resolution(new_width, new_height, nil)
    Kernel.pbMessage(_INTL("Pantalla cambiada a {1}.", current_label))
  end

  def self.open_menu
    if !resize_supported?
      Kernel.pbMessage(_INTL("Este motor no permite cambiar la resolucion desde script."))
      return
    end
    loop do
      commands = [
        _INTL("Auto pantalla: {1}", auto? ? "ON" : "OFF"),
        _INTL("Preset: {1}", current_label),
        _INTL("Resolucion personalizada"),
        _INTL("Aplicar otra vez"),
        _INTL("Restaurar clasico 4:3"),
        _INTL("Salir")
      ]
      cmd = Kernel.pbMessage(_INTL("Pantalla/Zoom\nActual: {1}", current_label), commands, commands.length)
      case cmd
      when 0
        set_auto_resolution
        Kernel.pbMessage(_INTL("Auto pantalla activado: {1}.", current_label))
      when 1
        choose_preset
      when 2
        custom_resolution
      when 3
        if apply(true)
          Kernel.pbMessage(_INTL("Pantalla aplicada: {1}.", current_label))
        end
      when 4
        set_resolution(512, 384, 0)
        Kernel.pbMessage(_INTL("Pantalla restaurada a 512x384."))
      else
        break
      end
    end
  end
end

class Object
  unless method_defined?(:sebi_controls_pbDrawTextPositions_without_labels) ||
         private_method_defined?(:sebi_controls_pbDrawTextPositions_without_labels)
    alias sebi_controls_pbDrawTextPositions_without_labels pbDrawTextPositions

    def pbDrawTextPositions(bitmap, textpos)
      if textpos
        changed = false
        new_textpos = []
        for entry in textpos
          if entry && entry[0].is_a?(String)
            copy = entry.clone
            heal_key = defined?(SebiControls) ? SebiControls.button_label(Input::X, "X") : "X"
            travel_key = defined?(SebiControls) ? SebiControls.button_label(Input::Y, "Y") : "Y"
            compass_key = defined?(SebiControls) ? SebiControls.button_label(Input::Z, "D") : "D"
            copy[0] = copy[0].gsub(/\[[^\]]+\]\s*Curar/, "[#{heal_key}] Curar")
            copy[0] = copy[0].gsub(/\[[^\]]+\]\s*Viajar/, "[#{travel_key}] Viajar")
            copy[0] = copy[0].sub(/\[[^\]]+\]/, "[#{compass_key}]") if copy[0].include?("jula")
            changed = true if copy[0] != entry[0]
            new_textpos.push(copy)
          else
            new_textpos.push(entry)
          end
        end
        textpos = new_textpos if changed
      end
      return sebi_controls_pbDrawTextPositions_without_labels(bitmap, textpos)
    end
  end
end

if defined?(PokemonSystem) && defined?(Keys)
  class PokemonSystem
    attr_accessor :gameControls

    unless method_defined?(:sebi_controls_gameControls_marker)
      def sebi_controls_gameControls_marker; end
      def gameControls
        @gameControls = Keys.defaultControls if !@gameControls
        return @gameControls
      end
    end

    unless method_defined?(:getGameControlCodes)
      def getGameControlCodes(controlAction)
        ret = []
        for control in gameControls
          ret.push(control.keyCode) if control && control.controlAction == controlAction
        end
        return ret
      end
    end
  end
end

module SebiControls
  ACTION_ACCEPT = _INTL("Aceptar")
  ACTION_BACK_RUN = _INTL("Cancelar/Pausa")
  ACTION_RUN_TOGGLE = _INTL("Correr/Acción")
  ACTION_TURBO = _INTL("Turbo")
  ACTION_BAG = _INTL("Curar")
  ACTION_MAIN_MENU = _INTL("Vuelo")
  ACTION_DB = _INTL("PokemonDB")
  ACTION_REGISTERED = _INTL("Obj. registrado")
  ACTION_COMPASS = _INTL("Radar")
  LEGACY_COMPASS = _INTL("Brujula")
  ACTION_BUTTON_A = ACTION_ACCEPT
  ACTION_BUTTON_B = ACTION_BACK_RUN
  ACTION_BUTTON_X = ACTION_BAG
  ACTION_BUTTON_Y = ACTION_MAIN_MENU
  ACTION_DEBOUNCE_FRAMES = 8
  @in_map_update = false
  @loaded_file_controls = false
  @free_text_cancel_nil = false
  @battle_bag_input = false
  @battle_bag_accept_pressed = false
  @normal_bag_input = false
  @normal_bag_accept_pressed = false

  def self.free_text_cancel_nil=(value)
    @free_text_cancel_nil = value ? true : false
  end

  def self.free_text_cancel_nil?
    return @free_text_cancel_nil ? true : false
  end

  def self.battle_bag_input=(value)
    @battle_bag_input = value ? true : false
  end

  def self.battle_bag_input?
    return @battle_bag_input ? true : false
  rescue Exception
    return false
  end

  def self.normal_bag_input=(value)
    @normal_bag_input = value ? true : false
  end

  def self.normal_bag_input?
    return @normal_bag_input ? true : false
  rescue Exception
    return false
  end

  def self.debounce_trigger_button?(button)
    return false if !defined?(Input)
    return false if button == Input::UP || button == Input::DOWN ||
                    button == Input::LEFT || button == Input::RIGHT
    return true
  rescue Exception
    return true
  end

  def self.allow_trigger?(button)
    return true
  rescue Exception
    return true
  end

  def self.legacy_control_action_map
    return {
      _INTL("Aceptar") => ACTION_ACCEPT,
      _INTL("Boton A - Seleccionar") => ACTION_ACCEPT,
      _INTL("Atras/Correr") => ACTION_BACK_RUN,
      _INTL("Boton B - Atras/Correr") => ACTION_BACK_RUN,
      _INTL("Cancelar/Pausa") => ACTION_BACK_RUN,
      _INTL("Alternar correr") => ACTION_RUN_TOGGLE,
      _INTL("Correr/Accion") => ACTION_RUN_TOGGLE,
      _INTL("Correr/Acción") => ACTION_RUN_TOGGLE,
      _INTL("Curar") => ACTION_BAG,
      _INTL("Bolsa") => ACTION_BAG,
      _INTL("Boton X - Secundario") => ACTION_BAG,
      _INTL("Menu principal") => ACTION_MAIN_MENU,
      _INTL("Boton Y - Menu principal") => ACTION_MAIN_MENU,
      _INTL("Vuelo") => ACTION_MAIN_MENU,
      _INTL("Brujula") => ACTION_COMPASS,
      LEGACY_COMPASS => ACTION_COMPASS
    }
  rescue Exception
    return {}
  end

  def self.migrate_legacy_control_actions
    return if !$PokemonSystem || !$PokemonSystem.gameControls
    map = legacy_control_action_map
    for control in $PokemonSystem.gameControls
      next if !control
      mapped = map[control.controlAction]
      control.instance_variable_set(:@controlAction, mapped) if mapped
    end
  rescue Exception
  end

  def self.action_debounce_key(action)
    return :button_a if action == ACTION_ACCEPT
    return :button_b if action == ACTION_BACK_RUN
    return :button_x if action == ACTION_BAG
    return :button_y if action == ACTION_MAIN_MENU
    return nil
  rescue Exception
    return nil
  end

  def self.allow_action_trigger?(action)
    return true
  rescue Exception
    return true
  end

  def self.debounce_action_for_button(button)
    return nil if !defined?(Input)
    return ACTION_ACCEPT if button == Input::C
    return ACTION_BACK_RUN if button == Input::B
    return ACTION_BAG if button == Input::X
    return ACTION_MAIN_MENU if button == Input::Y
    return nil
  rescue Exception
    return nil
  end

  def self.mark_action_debounce_for_button(button, frame)
    action = debounce_action_for_button(button)
    return if !action
    key = action_debounce_key(action)
    return if !key
    @action_debounce_frames ||= {}
    @action_debounce_frames[key] = frame
  rescue Exception
  end

  def self.mark_button_debounce_for_action(action, frame)
    @trigger_debounce_frames ||= {}
    for button in action_logical_buttons(action)
      next if !button
      key = button.to_i rescue button.object_id
      @trigger_debounce_frames[key] = frame
    end
  rescue Exception
  end

  def self.ensure_game_controls
    return if !defined?(Keys) || !defined?(PokemonSystem)
    $PokemonSystem = PokemonSystem.new if !$PokemonSystem
    migrate_legacy_control_actions
    actions = []
    for control in $PokemonSystem.gameControls
      actions.push(control.controlAction) if control
    end
    needed = [ACTION_ACCEPT, ACTION_BACK_RUN, ACTION_RUN_TOGGLE, ACTION_TURBO,
              ACTION_REGISTERED, _INTL("Desp. abajo"), _INTL("Desp. arriba"),
              ACTION_BAG, ACTION_MAIN_MENU, ACTION_COMPASS]
    missing = false
    for action in needed
      missing = true if !actions.include?(action)
    end
    if missing
      $PokemonSystem.gameControls = Keys.defaultControls
      @file_controls_system = nil
      @loaded_file_controls = false
    end
    load_file_controls
  rescue Exception
  end

  def self.load_file_controls
    return if !$PokemonSystem || !defined?(SebiLinkFileConfig)
    return if @file_controls_system.equal?($PokemonSystem) && (@file_controls_had_trainer || !$Trainer)
    controls = $PokemonSystem.gameControls
    changes = {}
    controls.each_with_index do |control, index|
      next if !control
      key = "control_" + index.to_s
      if SebiLinkFileConfig.needs_migration?(key)
        changes[key] = control.keyCode.to_i if $Trainer
      else
        code = SebiLinkFileConfig.get_int(key, control.keyCode.to_i)
        control.keyCode = code if code >= 0 && code <= 65535
      end
    end
    SebiLinkFileConfig.set_many(changes) if !changes.empty?
    @file_controls_system = $PokemonSystem
    @file_controls_had_trainer = $Trainer != nil
    @loaded_file_controls = true
  rescue Exception
  end

  def self.save_file_controls
    return if !$PokemonSystem || !defined?(SebiLinkFileConfig)
    changes = {}
    $PokemonSystem.gameControls.each_with_index do |control, index|
      changes["control_" + index.to_s] = control.keyCode.to_i if control
    end
    SebiLinkFileConfig.set_many(changes)
    @file_controls_system = $PokemonSystem
    @file_controls_had_trainer = $Trainer != nil
  rescue Exception
  end

  def self.detect_key_with_prompt(action)
    msgwindow = nil
    begin
      msgwindow = Kernel.pbCreateMessageWindow
      msgwindow.letterbyletter = false if msgwindow.respond_to?(:letterbyletter=)
      msgwindow.text = _INTL("Pulsa la nueva tecla o boton para {1}.", action)
      if defined?(Keys) && Keys.const_defined?("CONTROLSLIST")
        loop do
          Graphics.update
          Input.update
          msgwindow.update if msgwindow && msgwindow.respond_to?(:update)
          pressed = false
          for keyCode in Keys::CONTROLSLIST.values
            pressed = true if Input.pressex?(keyCode)
          end
          for pair in xinput_buttons
            pressed = true if xinput_press?(pair[0])
          end
          for pair in virtual_buttons
            pressed = true if virtual_press?(pair[0])
          end
          break if !pressed
        end
      end
      loop do
        Graphics.update
        Input.update
        msgwindow.update if msgwindow && msgwindow.respond_to?(:update)
        if defined?(Keys) && Keys.const_defined?("CONTROLSLIST")
          for keyCode in Keys::CONTROLSLIST.values
            if Input.triggerex?(keyCode)
              Kernel.pbDisposeMessageWindow(msgwindow) if msgwindow
              msgwindow = nil
              Input.update
              return keyCode
            end
          end
          for pair in xinput_buttons
            if xinput_trigger?(pair[0])
              Kernel.pbDisposeMessageWindow(msgwindow) if msgwindow
              msgwindow = nil
              Input.update
              return xinput_code(pair[0])
            end
          end
          for pair in virtual_buttons
            if virtual_trigger?(pair[0])
              Kernel.pbDisposeMessageWindow(msgwindow) if msgwindow
              msgwindow = nil
              Input.update
              return virtual_code(pair[0])
            end
          end
        else
          key = Keys.detectKey
          Kernel.pbDisposeMessageWindow(msgwindow) if msgwindow
          msgwindow = nil
          return key
        end
      end
    ensure
      begin
        Kernel.pbDisposeMessageWindow(msgwindow) if msgwindow && !msgwindow.disposed?
      rescue Exception
      end
    end
    return nil
  rescue Exception
    return Keys.detectKey
  end

  def self.game_control_codes(action)
    ensure_game_controls
    codes = []
    begin
      codes = $PokemonSystem.getGameControlCodes(action) if $PokemonSystem && $PokemonSystem.respond_to?(:getGameControlCodes)
    rescue Exception
      codes = []
    end
    if (!codes || codes.length == 0) && action == ACTION_COMPASS
      begin
        codes = $PokemonSystem.getGameControlCodes(LEGACY_COMPASS) if $PokemonSystem && $PokemonSystem.respond_to?(:getGameControlCodes)
      rescue Exception
        codes = []
      end
    end
    return codes || []
  rescue Exception
    return []
  end

  def self.action_key_name(action, fallback = "?")
    codes = game_control_codes(action)
    for code in codes
      next if !code || code.to_i == 0
      return xinput_name(code.to_i) if xinput_code?(code.to_i)
      return virtual_name(code.to_i) if code.to_i < 0
      return Keys.getKeyName(code.to_i) if defined?(Keys) && Keys.respond_to?(:getKeyName)
    end
    return fallback
  rescue Exception
    return fallback
  end

  def self.action_button_label(action, fallback = "?")
    label = action_key_name(action, fallback).to_s
    label = label.sub(/\AMando\s+/, "")
    label = label.sub(/\ACruceta\s+/, "")
    return label == "" ? fallback : label
  rescue Exception
    return fallback
  end

  def self.virtual_code(button)
    return -1000 - button.to_i
  rescue Exception
    return 0
  end

  def self.virtual_button(code)
    value = code.to_i
    return nil if value >= 0
    return (-1000 - value)
  rescue Exception
    return nil
  end

  def self.virtual_buttons
    return [] if !defined?(Input)
    buttons = []
    buttons.push([Input::C, _INTL("Mando A")]) if defined?(Input::C)
    buttons.push([Input::B, _INTL("Mando B")]) if defined?(Input::B)
    buttons.push([Input::X, _INTL("Mando X")]) if defined?(Input::X)
    buttons.push([Input::Y, _INTL("Mando Y")]) if defined?(Input::Y)
    buttons.push([Input::A, _INTL("Mando correr")]) if defined?(Input::A)
    buttons.push([Input::Z, _INTL("Mando Z")]) if defined?(Input::Z)
    buttons.push([Input::L, _INTL("Mando LB")]) if defined?(Input::L)
    buttons.push([Input::R, _INTL("Mando RB")]) if defined?(Input::R)
    buttons.push([Input::UP, _INTL("Mando arriba")]) if defined?(Input::UP)
    buttons.push([Input::DOWN, _INTL("Mando abajo")]) if defined?(Input::DOWN)
    buttons.push([Input::LEFT, _INTL("Mando izquierda")]) if defined?(Input::LEFT)
    buttons.push([Input::RIGHT, _INTL("Mando derecha")]) if defined?(Input::RIGHT)
    return buttons
  rescue Exception
    return []
  end

  def self.virtual_name(code)
    button = virtual_button(code)
    for pair in virtual_buttons
      return pair[1] if pair[0] == button
    end
    return _INTL("Mando ?")
  rescue Exception
    return _INTL("Mando ?")
  end

  def self.virtual_trigger?(button)
    return false if !defined?(Input)
    if Input.respond_to?(:sebi_controls_trigger_without_mod?)
      return true if Input.sebi_controls_trigger_without_mod?(button)
    else
      return true if Input.trigger?(button)
    end
    return false
  rescue Exception
    return false
  end

  def self.virtual_press?(button)
    return false if !defined?(Input)
    if Input.respond_to?(:sebi_controls_press_without_mod?)
      return true if Input.sebi_controls_press_without_mod?(button)
    else
      return true if Input.press?(button)
    end
    return false
  rescue Exception
    return false
  end

  def self.logical_trigger?(button)
    return false if !defined?(Input)
    if Input.respond_to?(:sebi_controls_trigger_without_mod?)
      return Input.sebi_controls_trigger_without_mod?(button)
    end
    return Input.trigger?(button)
  rescue Exception
    return false
  end

  def self.logical_press?(button)
    return false if !defined?(Input)
    if Input.respond_to?(:sebi_controls_press_without_mod?)
      return Input.sebi_controls_press_without_mod?(button)
    end
    return Input.press?(button)
  rescue Exception
    return false
  end

  def self.action_logical_buttons(action)
    return [] if !defined?(Input)
    if action == ACTION_ACCEPT
      buttons = []
      buttons.push(Input::C) if defined?(Input::C)
      return buttons
    elsif action == ACTION_BACK_RUN
      return defined?(Input::B) ? [Input::B] : []
    elsif action == ACTION_RUN_TOGGLE
      return defined?(Input::A) ? [Input::A] : []
    elsif action == ACTION_BAG
      buttons = []
      buttons.push(Input::X) if defined?(Input::X)
      return buttons
    elsif action == ACTION_MAIN_MENU
      return defined?(Input::Y) ? [Input::Y] : []
    elsif action == ACTION_COMPASS || action == LEGACY_COMPASS
      return defined?(Input::Z) ? [Input::Z] : []
    elsif action == _INTL("Desp. arriba")
      return defined?(Input::L) ? [Input::L] : []
    elsif action == _INTL("Desp. abajo")
      return defined?(Input::R) ? [Input::R] : []
    end
    return []
  rescue Exception
    return []
  end

  def self.xinput_code(id)
    return -2000 - id.to_i
  rescue Exception
    return 0
  end

  def self.xinput_id(code)
    value = code.to_i
    return nil if value > -2001
    return -2000 - value
  rescue Exception
    return nil
  end

  def self.xinput_code?(code)
    return code.to_i <= -2001
  rescue Exception
    return false
  end

  def self.xinput_buttons
    return [
      [1,  _INTL("Mando A"),       :button, 0x1000],
      [2,  _INTL("Mando B"),       :button, 0x2000],
      [3,  _INTL("Mando X"),       :button, 0x4000],
      [4,  _INTL("Mando Y"),       :button, 0x8000],
      [5,  _INTL("Mando LB"),      :button, 0x0100],
      [6,  _INTL("Mando RB"),      :button, 0x0200],
      [7,  _INTL("Mando LT"),      :trigger, :left],
      [8,  _INTL("Mando RT"),      :trigger, :right],
      [9,  _INTL("Mando -"),       :button, 0x0020],
      [10, _INTL("Mando +"),       :button, 0x0010],
      [11, _INTL("Stick L"),       :button, 0x0040],
      [12, _INTL("Stick R"),       :button, 0x0080],
      [13, _INTL("Cruceta arriba"), :button, 0x0001],
      [14, _INTL("Cruceta abajo"),  :button, 0x0002],
      [15, _INTL("Cruceta izquierda"), :button, 0x0004],
      [16, _INTL("Cruceta derecha"),   :button, 0x0008]
    ]
  rescue Exception
    return []
  end

  def self.xinput_name(code)
    id = xinput_id(code)
    for pair in xinput_buttons
      return pair[1] if pair[0] == id
    end
    return _INTL("Mando ?")
  rescue Exception
    return _INTL("Mando ?")
  end

  def self.xinput_api
    return @xinput_api if @xinput_api_checked
    @xinput_api_checked = true
    @xinput_api = nil
    return nil if !defined?(Win32API)
    for dll in ["xinput1_4", "xinput1_3", "xinput9_1_0"]
      begin
        @xinput_api = Win32API.new(dll, "XInputGetState", "lp", "l")
        break
      rescue Exception
      end
    end
    return @xinput_api
  rescue Exception
    return nil
  end

  def self.xinput_read_bits
    api = xinput_api
    return 0 if !api
    bits = 0
    for controller in 0...4
      state = "\0" * 16
      next if api.call(controller, state) != 0
      data = state.unpack("LSCCssss") rescue nil
      next if !data || data.length < 4
      buttons = data[1].to_i
      left_trigger = data[2].to_i
      right_trigger = data[3].to_i
      for entry in xinput_buttons
        id = entry[0]
        kind = entry[2]
        value = entry[3]
        pressed = false
        pressed = (buttons & value.to_i) != 0 if kind == :button
        pressed = left_trigger > 30 if kind == :trigger && value == :left
        pressed = right_trigger > 30 if kind == :trigger && value == :right
        bits |= (1 << id) if pressed
      end
    end
    return bits
  rescue Exception
    return 0
  end

  def self.xinput_bits
    frame = Graphics.frame_count rescue 0
    if @xinput_frame != frame
      @xinput_prev_bits = @xinput_current_bits || 0
      @xinput_current_bits = xinput_read_bits
      @xinput_frame = frame
    end
    return @xinput_current_bits || 0
  rescue Exception
    return 0
  end

  def self.xinput_press?(id)
    return (xinput_bits & (1 << id.to_i)) != 0
  rescue Exception
    return false
  end

  def self.xinput_trigger?(id)
    bit = (1 << id.to_i)
    current = xinput_bits
    previous = @xinput_prev_bits || 0
    return (current & bit) != 0 && (previous & bit) == 0
  rescue Exception
    return false
  end

  def self.button_label(button, fallback = "?")
    case button
    when Input::X
      return action_button_label(ACTION_BAG, fallback)
    when Input::Y
      return action_button_label(ACTION_MAIN_MENU, fallback)
    when Input::Z
      return action_button_label(ACTION_COMPASS, fallback)
    when Input::A
      return action_button_label(ACTION_RUN_TOGGLE, fallback)
    when Input::C
      return action_button_label(ACTION_ACCEPT, fallback)
    when Input::B
      return action_button_label(ACTION_BACK_RUN, fallback)
    end
    return fallback
  rescue Exception
    return fallback
  end

  def self.open_menu
    if !defined?(Keys) || !defined?(ControlConfig) || !defined?(PokemonSystem)
      Kernel.pbMessage(_INTL("El menu de controles no esta disponible en este motor."))
      return
    end
    ensure_game_controls
    loop do
      controls = $PokemonSystem.gameControls
      commands = []
      for control in controls
        commands.push(_INTL("{1}: {2}", control.controlAction, control.keyName))
      end
      commands.push(_INTL("Restaurar controles por defecto"))
      commands.push(_INTL("Ayuda"))
      commands.push(_INTL("Salir"))
      cmd = Kernel.pbMessage(_INTL("Controles"), commands, commands.length)
      break if cmd < 0 || cmd >= commands.length - 1
      if cmd < controls.length
        new_key = detect_key_with_prompt(controls[cmd].controlAction)
        next if !new_key
        for i in 0...controls.length
          next if i == cmd
          controls[i].keyCode = 0 if controls[i] && controls[i].keyCode == new_key
        end
        controls[cmd].keyCode = new_key
        save_file_controls
        Kernel.pbMessage(_INTL("{1} ahora usa {2}.", controls[cmd].controlAction, controls[cmd].keyName))
      elsif cmd == controls.length
        if Kernel.pbConfirmMessage(_INTL("Restaurar los controles por defecto?"))
          $PokemonSystem.gameControls = Keys.defaultControls
          @loaded_file_controls = false
          save_file_controls
        end
      else
        Kernel.pbMessage(_INTL("Controles originales: Aceptar usa C/Enter, Cancelar/Pausa usa X/Esc, Correr/Accion usa Z, Turbo usa Alt, Curar usa A, Vuelo usa S y Radar usa D."))
      end
    end
    save_file_controls
  end

  def self.action_trigger?(action)
    return false if !defined?(Input)
    triggered = false
    codes = game_control_codes(action)
    for code in codes
      next if !code
      value = code.to_i
      if value > 0 && Input.respond_to?(:triggerex?) && Input.triggerex?(value)
        triggered = true
        break
      elsif xinput_code?(value) && xinput_trigger?(xinput_id(value))
        triggered = true
        break
      elsif value < 0 && !xinput_code?(value) && virtual_trigger?(virtual_button(value))
        triggered = true
        break
      end
    end
    if !triggered
      for button in action_logical_buttons(action)
        if logical_trigger?(button)
          triggered = true
          break
        end
      end
    end
    return false if !triggered
    return allow_action_trigger?(action)
  rescue Exception
    return false
  end

  def self.action_press?(action)
    return false if !defined?(Input)
    codes = game_control_codes(action)
    for code in codes
      next if !code
      value = code.to_i
      return true if value > 0 && Input.respond_to?(:pressex?) && Input.pressex?(value)
      return true if xinput_code?(value) && xinput_press?(xinput_id(value))
      return true if value < 0 && !xinput_code?(value) && virtual_press?(virtual_button(value))
    end
    for button in action_logical_buttons(action)
      return true if logical_press?(button)
    end
    return false
  rescue Exception
    return false
  end

  def self.accept_press?
    return true if action_press?(ACTION_ACCEPT)
    return true if Input.respond_to?(:sebi_controls_press_without_mod?) &&
                   Input.sebi_controls_press_without_mod?(Input::C)
    return false
  rescue Exception
    return false
  end

  def self.battle_bag_accept_pressed_now?
    pressed = false
    pressed = true if accept_press?
    pressed = true if Input.respond_to?(:sebi_controls_trigger_without_mod?) &&
                      Input.sebi_controls_trigger_without_mod?(Input::C)
    return pressed
  rescue Exception
    return false
  end

  def self.battle_bag_accept_trigger_now?
    triggered = false
    triggered = true if action_trigger?(ACTION_ACCEPT)
    if Input.respond_to?(:sebi_controls_trigger_without_mod?) &&
       Input.sebi_controls_trigger_without_mod?(Input::C)
      triggered = true if allow_action_trigger?(ACTION_ACCEPT)
    end
    return triggered
  rescue Exception
    return false
  end

  def self.prime_battle_bag_accept
    @battle_bag_accept_pressed = battle_bag_accept_pressed_now?
    @battle_bag_last_accept_frame = Graphics.frame_count if @battle_bag_accept_pressed
  rescue Exception
    @battle_bag_accept_pressed = false
  end

  def self.battle_bag_accept_edge?
    return false if !battle_bag_input?
    return false if battle_bag_accept_consumed?
    pressed = battle_bag_accept_pressed_now?
    frame = Graphics.frame_count rescue 0
    triggered = battle_bag_accept_trigger_now?
    edge = pressed && !@battle_bag_accept_pressed
    recent = @battle_bag_last_accept_frame && frame - @battle_bag_last_accept_frame < 8
    ret = (triggered || edge) && !recent
    @battle_bag_last_accept_frame = frame if ret
    @battle_bag_accept_consumed_frame = frame if ret
    @battle_bag_accept_pressed = pressed
    return ret
  rescue Exception
    @battle_bag_accept_pressed = false
    return false
  end

  def self.battle_bag_accept_consumed?
    return @battle_bag_accept_consumed_frame == Graphics.frame_count
  rescue Exception
    return false
  end

  def self.battle_bag_accept_recent?
    frame = Graphics.frame_count rescue 0
    return false if !@battle_bag_last_accept_frame
    return frame - @battle_bag_last_accept_frame < 8
  rescue Exception
    return false
  end

  def self.normal_bag_accept_pressed_now?
    pressed = false
    pressed = true if accept_press?
    pressed = true if Input.respond_to?(:sebi_controls_trigger_without_mod?) &&
                      Input.sebi_controls_trigger_without_mod?(Input::C)
    return pressed
  rescue Exception
    return false
  end

  def self.normal_bag_accept_trigger_now?
    triggered = false
    triggered = true if action_trigger?(ACTION_ACCEPT)
    if Input.respond_to?(:sebi_controls_trigger_without_mod?) &&
       Input.sebi_controls_trigger_without_mod?(Input::C)
      triggered = true if allow_action_trigger?(ACTION_ACCEPT)
    end
    return triggered
  rescue Exception
    return false
  end

  def self.prime_normal_bag_accept
    @normal_bag_accept_pressed = normal_bag_accept_pressed_now?
    @normal_bag_last_accept_frame = Graphics.frame_count if @normal_bag_accept_pressed
  rescue Exception
    @normal_bag_accept_pressed = false
  end

  def self.normal_bag_accept_edge?
    return false if !normal_bag_input?
    return false if normal_bag_accept_consumed?
    pressed = normal_bag_accept_pressed_now?
    frame = Graphics.frame_count rescue 0
    triggered = normal_bag_accept_trigger_now?
    edge = pressed && !@normal_bag_accept_pressed
    recent = @normal_bag_last_accept_frame && frame - @normal_bag_last_accept_frame < 8
    ret = (triggered || edge) && !recent
    @normal_bag_last_accept_frame = frame if ret
    @normal_bag_accept_consumed_frame = frame if ret
    @normal_bag_accept_pressed = pressed
    return ret
  rescue Exception
    @normal_bag_accept_pressed = false
    return false
  end

  def self.normal_bag_accept_consumed?
    return @normal_bag_accept_consumed_frame == Graphics.frame_count
  rescue Exception
    return false
  end

  def self.normal_bag_accept_recent?
    frame = Graphics.frame_count rescue 0
    return false if !@normal_bag_last_accept_frame
    return frame - @normal_bag_last_accept_frame < 8
  rescue Exception
    return false
  end

  def self.with_normal_bag_input
    old_context = normal_bag_input?
    self.normal_bag_input = true
    prime_normal_bag_accept
    return yield
  ensure
    self.normal_bag_input = old_context
  end

  def self.raw_key_press?(key)
    begin
      @sebi_get_async_key_state = Win32API.new("user32", "GetAsyncKeyState", "i", "i") if !@sebi_get_async_key_state && defined?(Win32API)
      return false if !@sebi_get_async_key_state
      return (@sebi_get_async_key_state.call(key.to_i) & 0x8000) != 0
    rescue Exception
      return false
    end
  end

  def self.apply_battle_bag_accept(window)
    return
  rescue Exception
  end

  def self.install_battle_bag_controls_patch
    return if !defined?(NewBattleBag)
    klass = NewBattleBag
    unless klass.method_defined?(:sebi_controls_accept)
      klass.class_eval do
        def sebi_controls_accept
          if @selPocket == 0
            if !@doubleback && @index.to_i < 5
              confirm
            elsif !@doubleback && @index.to_i == 5
              finish
            end
          elsif !@back
            intoPocket
          end
        end
      end
    end
    unless klass.method_defined?(:sebi_controls_update_without_bag_accept_context)
      klass.class_eval do
        alias sebi_controls_update_without_bag_accept_context update

        def update
          old_context = defined?(SebiControls) ? SebiControls.battle_bag_input? : false
          SebiControls.battle_bag_input = true if defined?(SebiControls)
          SebiControls.apply_battle_bag_accept(self) if defined?(SebiControls)
          ret = sebi_controls_update_without_bag_accept_context
          SebiControls.apply_battle_bag_accept(self) if defined?(SebiControls)
          return ret
        ensure
          SebiControls.battle_bag_input = old_context if defined?(SebiControls)
        end
      end
    end
    unless klass.method_defined?(:sebi_controls_useItem_without_bag_accept_context?)
      klass.class_eval do
        alias sebi_controls_useItem_without_bag_accept_context? useItem?

        def useItem?
          old_context = defined?(SebiControls) ? SebiControls.battle_bag_input? : false
          SebiControls.battle_bag_input = true if defined?(SebiControls)
          SebiControls.prime_battle_bag_accept if defined?(SebiControls)
          return sebi_controls_useItem_without_bag_accept_context?
        ensure
          SebiControls.battle_bag_input = old_context if defined?(SebiControls)
        end
      end
    end
  rescue Exception
  end

  def self.install_normal_bag_controls_patch
    return if !defined?(PokemonBag_Scene)
    klass = PokemonBag_Scene
    unless klass.method_defined?(:sebi_controls_pbChooseItem_without_normal_bag_input)
      klass.class_eval do
        alias sebi_controls_pbChooseItem_without_normal_bag_input pbChooseItem

        def pbChooseItem(lockpocket = false)
          if defined?(SebiControls)
            return SebiControls.with_normal_bag_input { sebi_controls_pbChooseItem_without_normal_bag_input(lockpocket) }
          end
          return sebi_controls_pbChooseItem_without_normal_bag_input(lockpocket)
        end
      end
    end
    unless klass.method_defined?(:sebi_controls_pbShowCommands_without_normal_bag_input)
      klass.class_eval do
        alias sebi_controls_pbShowCommands_without_normal_bag_input pbShowCommands

        def pbShowCommands(helptext, commands)
          if defined?(SebiControls)
            return SebiControls.with_normal_bag_input { sebi_controls_pbShowCommands_without_normal_bag_input(helptext, commands) }
          end
          return sebi_controls_pbShowCommands_without_normal_bag_input(helptext, commands)
        end
      end
    end
    unless klass.method_defined?(:sebi_controls_pbConfirm_without_normal_bag_input)
      klass.class_eval do
        alias sebi_controls_pbConfirm_without_normal_bag_input pbConfirm

        def pbConfirm(msg)
          if defined?(SebiControls)
            return SebiControls.with_normal_bag_input { sebi_controls_pbConfirm_without_normal_bag_input(msg) }
          end
          return sebi_controls_pbConfirm_without_normal_bag_input(msg)
        end
      end
    end
    unless klass.method_defined?(:sebi_controls_pbChooseNumber_without_normal_bag_input)
      klass.class_eval do
        alias sebi_controls_pbChooseNumber_without_normal_bag_input pbChooseNumber

        def pbChooseNumber(helptext, maximum)
          if defined?(SebiControls)
            return SebiControls.with_normal_bag_input { sebi_controls_pbChooseNumber_without_normal_bag_input(helptext, maximum) }
          end
          return sebi_controls_pbChooseNumber_without_normal_bag_input(helptext, maximum)
        end
      end
    end
    unless klass.method_defined?(:sebi_controls_pbDisplay_without_normal_bag_input)
      klass.class_eval do
        alias sebi_controls_pbDisplay_without_normal_bag_input pbDisplay

        def pbDisplay(msg, brief = false)
          if defined?(SebiControls)
            return SebiControls.with_normal_bag_input { sebi_controls_pbDisplay_without_normal_bag_input(msg, brief) }
          end
          return sebi_controls_pbDisplay_without_normal_bag_input(msg, brief)
        end
      end
    end
  rescue Exception
  end

  def self.accept_trigger?
    return true if action_trigger?(ACTION_ACCEPT)
    if Input.respond_to?(:sebi_controls_trigger_without_mod?) &&
       Input.sebi_controls_trigger_without_mod?(Input::C)
      return true if allow_action_trigger?(ACTION_ACCEPT)
    end
    return false
  rescue Exception
    return false
  end

  def self.back_trigger?
    return true if action_trigger?(ACTION_BACK_RUN)
    if Input.respond_to?(:sebi_controls_trigger_without_mod?) &&
       Input.sebi_controls_trigger_without_mod?(Input::B)
      return true if allow_action_trigger?(ACTION_BACK_RUN)
    end
    return false
  rescue Exception
    return false
  end

  def self.back_press?
    return true if action_press?(ACTION_BACK_RUN)
    return true if Input.respond_to?(:sebi_controls_press_without_mod?) &&
                   Input.sebi_controls_press_without_mod?(Input::B)
    return false
  rescue Exception
    return false
  end

  def self.button_a_trigger?
    return accept_trigger?
  rescue Exception
    return false
  end

  def self.button_b_trigger?
    return back_trigger?
  rescue Exception
    return false
  end

  def self.button_x_trigger?
    return action_trigger?(ACTION_BAG)
  rescue Exception
    return false
  end

  def self.button_y_trigger?
    return action_trigger?(ACTION_MAIN_MENU)
  rescue Exception
    return false
  end

  def self.menu_back_press?
    return false if suppress_map_cancel?
    return false if $scene && $scene.is_a?(Scene_Map) && (!$game_temp || !$game_temp.in_menu)
    return back_press?
  rescue Exception
    return false
  end

  def self.db_trigger?
    return SebiExtraControls.db_trigger? if defined?(SebiExtraControls)
    return true if action_trigger?(ACTION_DB)
    return Input.trigger?(Input::F3)
  rescue Exception
    return false
  end

  def self.f4_trigger?
    return false if !defined?(Input) || !Input.respond_to?(:triggerex?)
    return false if !Input.triggerex?(0x73)
    return allow_trigger?(0x73)
  rescue Exception
    return false
  end

  def self.party_level_scene=(scene)
    @party_level_scene = scene
  end

  def self.storage_level_scene=(scene)
    @storage_level_scene = scene
  end

  def self.handle_f4_level_shortcut
    return if @handling_f4_level_shortcut
    return if !defined?(SebiExtraControls) || !SebiExtraControls.level_trigger?
    return if $game_temp && $game_temp.in_battle
    @handling_f4_level_shortcut = true
    if @storage_level_scene && defined?(SebiCheats)
      storage = @storage_level_scene.instance_variable_get("@storage") rescue nil
      SebiCheats.equalize_current_box_levels(storage)
      @storage_level_scene.pbRefresh if @storage_level_scene.respond_to?(:pbRefresh)
    elsif @party_level_scene && defined?(SebiCheats)
      SebiCheats.equalize_party_levels
      @party_level_scene.pbRefresh if @party_level_scene.respond_to?(:pbRefresh)
    end
  rescue Exception
  ensure
    @handling_f4_level_shortcut = false
  end

  def self.handle_extra_level_shortcut
    handle_f4_level_shortcut
  rescue Exception
  end

  def self.cancel_pressed?
    return true if back_trigger?
    return false
  rescue Exception
    return false
  end

  def self.in_map_update=(value)
    @in_map_update = value ? true : false
  end

  def self.in_map_update?
    return @in_map_update ? true : false
  rescue Exception
    return false
  end

  def self.suppress_map_cancel?
    return false if !@in_map_update
    return false if !$scene || !$scene.is_a?(Scene_Map)
    return false if $game_temp && $game_temp.in_menu
    return false if $game_temp && $game_temp.message_window_showing
    return true
  rescue Exception
    return false
  end

  def self.map_shortcuts_available?
    return false if !$Trainer || !$game_player || !$game_map || !$game_temp
    return false if $game_temp.message_window_showing
    return false if $game_temp.battle_calling || $game_temp.transition_processing
    return false if $game_system && $game_system.menu_disabled
    return false if $game_player.moving?
    begin
      return false if pbMapInterpreterRunning?
    rescue Exception
    end
    return true
  end

  def self.open_bag_from_map
    return if !$PokemonBag
    $game_temp.in_menu = true if $game_temp
    $game_player.straighten if $game_player
    $game_map.update if $game_map
    item = 0
    pbFadeOutIn(99999) do
      scene = PokemonBag_Scene.new
      screen = PokemonBagScreen.new(scene, $PokemonBag)
      item = screen.pbStartScreen
    end
    Kernel.pbUseKeyItemInField(item) if item && item > 0
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir la bolsa."))
  ensure
    $game_temp.in_menu = false if $game_temp
  end

  def self.handle_map_shortcuts
    return false
    return false if !map_shortcuts_available?
    if button_x_trigger?
      open_bag_from_map
      return true
    elsif button_y_trigger?
      $game_temp.menu_calling = true
      $game_temp.menu_beep = true
      return false
    end
    return false
  end
end

module SebiExtraControls
  ACTION_DB = _INTL("Abrir PokemonDB")
  ACTION_WEAKNESS = _INTL("Mostrar debilidades")
  ACTION_LEVEL = _INTL("Igualar niveles")
  KEY_DB = "extra_control_pokemondb"
  KEY_WEAKNESS = "extra_control_weakness"
  KEY_LEVEL = "extra_control_level_sync"
  DEFAULT_DB_KEY = 0x72
  DEFAULT_WEAKNESS_KEY = 0x73
  DEFAULT_LEVEL_KEY = 0x75
  RESERVED_XINPUT_IDS = [1, 2, 3, 4, 5, 6, 13, 14, 15, 16]
  TRIGGER_COOLDOWN_FRAMES = 8
  @last_trigger_frames = {}

  def self.key_code(config_key, default_value)
    return SebiLinkFileConfig.get_int(config_key, default_value) if defined?(SebiLinkFileConfig)
    return default_value
  rescue Exception
    return default_value
  end

  def self.set_key(config_key, value)
    SebiLinkFileConfig.set(config_key, value.to_i.to_s) if defined?(SebiLinkFileConfig)
  rescue Exception
  end

  def self.reserved_gameplay_actions
    return [] if !defined?(SebiControls)
    actions = []
    names = ["ACTION_ACCEPT", "ACTION_BACK_RUN", "ACTION_RUN_TOGGLE",
             "ACTION_BAG", "ACTION_MAIN_MENU", "ACTION_COMPASS"]
    for name in names
      actions.push(SebiControls.const_get(name)) if SebiControls.const_defined?(name)
    end
    return actions
  rescue Exception
    return []
  end

  def self.reserved_virtual_buttons
    return [] if !defined?(Input)
    buttons = []
    buttons.push(Input::C) if defined?(Input::C)
    buttons.push(Input::B) if defined?(Input::B)
    buttons.push(Input::A) if defined?(Input::A)
    buttons.push(Input::X) if defined?(Input::X)
    buttons.push(Input::Y) if defined?(Input::Y)
    buttons.push(Input::Z) if defined?(Input::Z)
    buttons.push(Input::L) if defined?(Input::L)
    buttons.push(Input::R) if defined?(Input::R)
    buttons.push(Input::UP) if defined?(Input::UP)
    buttons.push(Input::DOWN) if defined?(Input::DOWN)
    buttons.push(Input::LEFT) if defined?(Input::LEFT)
    buttons.push(Input::RIGHT) if defined?(Input::RIGHT)
    return buttons
  rescue Exception
    return []
  end

  def self.reserved_gameplay_key?(value)
    return false if !defined?(SebiControls)
    value = value.to_i
    return false if value == 0
    if SebiControls.xinput_code?(value)
      id = SebiControls.xinput_id(value)
      return RESERVED_XINPUT_IDS.include?(id.to_i)
    end
    if value < 0
      button = SebiControls.virtual_button(value)
      return reserved_virtual_buttons.include?(button)
    end
    for action in reserved_gameplay_actions
      for code in SebiControls.game_control_codes(action)
        return true if code && code.to_i == value
      end
    end
    return false
  rescue Exception
    return false
  end

  def self.normalized_key_code(config_key, default_value)
    value = key_code(config_key, default_value)
    if reserved_gameplay_key?(value)
      set_key(config_key, default_value)
      return default_value
    end
    return value
  rescue Exception
    return default_value
  end

  def self.db_key
    return normalized_key_code(KEY_DB, DEFAULT_DB_KEY)
  end

  def self.weakness_key
    return normalized_key_code(KEY_WEAKNESS, DEFAULT_WEAKNESS_KEY)
  end

  def self.level_key
    return normalized_key_code(KEY_LEVEL, DEFAULT_LEVEL_KEY)
  end

  def self.key_name(value)
    value = value.to_i
    return _INTL("Sin asignar") if value == 0
    if defined?(SebiControls)
      return SebiControls.xinput_name(value) if SebiControls.xinput_code?(value)
      return SebiControls.virtual_name(value) if value < 0
    end
    if defined?(Keys) && Keys.respond_to?(:getKeyName)
      name = Keys.getKeyName(value) rescue nil
      return name if name && name.to_s != ""
    end
    return "F3" if value == DEFAULT_DB_KEY
    return "F4" if value == DEFAULT_WEAKNESS_KEY
    return "F6" if value == DEFAULT_LEVEL_KEY
    return value.to_s
  rescue Exception
    return value.to_s
  end

  def self.db_key_name
    return key_name(db_key)
  end

  def self.weakness_key_name
    return key_name(weakness_key)
  end

  def self.level_key_name
    return key_name(level_key)
  end

  def self.trigger_code?(value)
    return false if !defined?(Input)
    value = value.to_i
    return false if value == 0
    if value > 0
      return Input.triggerex?(value) if Input.respond_to?(:triggerex?)
      return false
    end
    if defined?(SebiControls)
      return SebiControls.xinput_trigger?(SebiControls.xinput_id(value)) if SebiControls.xinput_code?(value)
      return SebiControls.virtual_trigger?(SebiControls.virtual_button(value))
    end
    return false
  rescue Exception
    return false
  end

  def self.extra_trigger?(config_key, default_value)
    value = normalized_key_code(config_key, default_value)
    return false if !trigger_code?(value)
    frame = Graphics.frame_count rescue 0
    @last_trigger_frames ||= {}
    last = @last_trigger_frames[config_key]
    return false if last && frame - last < TRIGGER_COOLDOWN_FRAMES
    @last_trigger_frames[config_key] = frame
    return true
  rescue Exception
    return false
  end

  def self.db_trigger?
    return extra_trigger?(KEY_DB, DEFAULT_DB_KEY)
  end

  def self.weakness_trigger?
    return extra_trigger?(KEY_WEAKNESS, DEFAULT_WEAKNESS_KEY)
  end

  def self.level_trigger?
    return extra_trigger?(KEY_LEVEL, DEFAULT_LEVEL_KEY)
  end

  def self.duplicate_key?(config_key, value)
    value = value.to_i
    return false if value == 0
    return true if config_key != KEY_DB && db_key == value
    return true if config_key != KEY_WEAKNESS && weakness_key == value
    return true if config_key != KEY_LEVEL && level_key == value
    return false
  rescue Exception
    return false
  end

  def self.assign_key(config_key, action_name)
    if !defined?(SebiControls)
      Kernel.pbMessage(_INTL("El detector de teclas no esta disponible."))
      return
    end
    new_key = SebiControls.detect_key_with_prompt(action_name)
    return if !new_key
    if reserved_gameplay_key?(new_key)
      Kernel.pbMessage(_INTL("Ese boton o tecla pertenece a los controles normales del juego. Usa una tecla libre para los controles extra."))
      return
    end
    if duplicate_key?(config_key, new_key)
      Kernel.pbMessage(_INTL("Esa tecla ya esta usada por otro control extra."))
      return
    end
    set_key(config_key, new_key)
    Kernel.pbMessage(_INTL("{1} ahora usa {2}.", action_name, key_name(new_key)))
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo cambiar este control extra."))
  end

  def self.reset_defaults
    set_key(KEY_DB, DEFAULT_DB_KEY)
    set_key(KEY_WEAKNESS, DEFAULT_WEAKNESS_KEY)
    set_key(KEY_LEVEL, DEFAULT_LEVEL_KEY)
  rescue Exception
  end

  def self.open_menu
    loop do
      commands = [
        _INTL("PokemonDB: {1}", db_key_name),
        _INTL("Debilidades combate: {1}", weakness_key_name),
        _INTL("Igualar niveles: {1}", level_key_name),
        _INTL("Restaurar controles extra"),
        _INTL("Ayuda"),
        _INTL("Salir")
      ]
      cmd = Kernel.pbMessage(_INTL("Controles extra"), commands, commands.length)
      case cmd
      when 0
        assign_key(KEY_DB, ACTION_DB)
      when 1
        assign_key(KEY_WEAKNESS, ACTION_WEAKNESS)
      when 2
        assign_key(KEY_LEVEL, ACTION_LEVEL)
      when 3
        if Kernel.pbConfirmMessage(_INTL("Restaurar controles extra por defecto?"))
          reset_defaults
        end
      when 4
        Kernel.pbMessage(_INTL("Estos controles solo son extras de SebiLink. No cambian los controles originales ni el menu F1. No uses botones normales como aceptar, cancelar, correr o la cruceta. Igualar niveles solo funciona fuera de combate en Equipo o PC."))
      else
        break
      end
    end
  end
end

if defined?(Keys) && defined?(ControlConfig)
  class << Keys
    unless method_defined?(:sebi_controls_defaultControls_without_mod)
      alias sebi_controls_defaultControls_without_mod defaultControls

      def defaultControls
        return sebi_controls_defaultControls_without_mod
      end
    end

    if method_defined?(:getKeyName) && !method_defined?(:sebi_controls_getKeyName_without_virtual_buttons)
      alias sebi_controls_getKeyName_without_virtual_buttons getKeyName

      def getKeyName(keyCode)
        return sebi_controls_getKeyName_without_virtual_buttons(keyCode)
      end
    end
  end
end

if defined?(Input)
  module Input
    class << self
      if method_defined?(:buttonToKey) && !method_defined?(:sebi_controls_buttonToKey_without_mod)
        alias sebi_controls_buttonToKey_without_mod buttonToKey

        def buttonToKey(button)
          SebiControls.ensure_game_controls if defined?(SebiControls)
          return sebi_controls_buttonToKey_without_mod(button)
        end
      end

      if method_defined?(:trigger?) && !method_defined?(:sebi_controls_trigger_without_mod?)
        alias sebi_controls_trigger_without_mod? trigger?

        def trigger?(button)
          return sebi_controls_trigger_without_mod?(button)
        end
      end

      if method_defined?(:press?) && !method_defined?(:sebi_controls_press_without_mod?)
        alias sebi_controls_press_without_mod? press?

        def press?(button)
          return sebi_controls_press_without_mod?(button)
        end
      end

      if method_defined?(:update) && !method_defined?(:sebi_controls_update_without_f4_shortcut)
        alias sebi_controls_update_without_f4_shortcut update

        def update
          if defined?(SebiSaveManager) && SebiSaveManager.respond_to?(:quick_window_key_down?) && SebiSaveManager.quick_window_key_down?
            ret = nil
          else
            ret = sebi_controls_update_without_f4_shortcut
          end
          SebiControls.handle_extra_level_shortcut if defined?(SebiControls)
          SebiSaveEditor.handle_shortcut if defined?(SebiSaveEditor)
          SebiSaveEditor.update if defined?(SebiSaveEditor)
          SebiLevelReview.update if defined?(SebiLevelReview)
          SebiCheats.handle_repel_shortcut if defined?(SebiCheats)
          SebiLinkHub.handle_shortcut if defined?(SebiLinkHub)
          SebiLinkHub.update if defined?(SebiLinkHub)
          SebiSaveManager.update if defined?(SebiSaveManager)
          return ret
        end
      end
    end
  end
end

if defined?(Keys)
  class << Keys
    if method_defined?(:detectKey) && !method_defined?(:sebi_controls_detectKey_without_release)
      alias sebi_controls_detectKey_without_release detectKey

      def detectKey
        return sebi_controls_detectKey_without_release
      end
    end
  end
end

if defined?(PokemonControls)
  class PokemonControls
    unless method_defined?(:sebi_controls_pbStartScreen_without_file_sync)
      alias sebi_controls_pbStartScreen_without_file_sync pbStartScreen

      def pbStartScreen
        SebiControls.ensure_game_controls if defined?(SebiControls)
        ret = sebi_controls_pbStartScreen_without_file_sync
        SebiControls.save_file_controls if defined?(SebiControls)
        return ret
      end
    end
  end
end

if defined?(DP_PauseMenu)
  class DP_PauseMenu
    unless method_defined?(:sebi_controls_update_without_f1_menu)
      alias sebi_controls_update_without_f1_menu update

      def update
        return sebi_controls_update_without_f1_menu
      end
    end
  end
end

class Game_Player
  unless method_defined?(:sebi_controls_pbCanRun_without_mod?)
    alias sebi_controls_pbCanRun_without_mod? pbCanRun?

    def pbCanRun?
      return sebi_controls_pbCanRun_without_mod?
    end
  end
end

class Scene_Map
  unless method_defined?(:sebi_controls_update_without_shortcuts)
    alias sebi_controls_update_without_shortcuts update

    def update
      return sebi_controls_update_without_shortcuts
    end
  end
end

class PokemonEntryScene
  unless method_defined?(:sebi_controls_pbEntry1_without_pad_buttons)
    alias sebi_controls_pbEntry1_without_pad_buttons pbEntry1

    def pbEntry1
      return sebi_controls_pbEntry1_without_pad_buttons
    end
  end
end

module Kernel
  class << self
    unless method_defined?(:sebi_controls_pbFreeText_without_pad_buttons)
      alias sebi_controls_pbFreeText_without_pad_buttons pbFreeText

      def pbFreeText(msgwindow, currenttext, passwordbox, maxlength, width = 240)
        return sebi_controls_pbFreeText_without_pad_buttons(msgwindow, currenttext, passwordbox, maxlength, width)
      end
    end
  end
end

module SebiAutoBackups
  INTERVAL_SECONDS = 300
  BACKUP_DIR_NAME = "SebiLinkAutoBackups"
  @next_backup_at = nil
  @last_message = nil

  def self.now_i
    return Time.now.to_i
  rescue Exception
    return 0
  end

  def self.save_number
    num = 1
    num = $game_variables[99].to_i if defined?($game_variables) && $game_variables
    num = 1 if num <= 1
    return num
  rescue Exception
    return 1
  end

  def self.original_filename_for_number(num)
    return "Game.rxdata" if num.to_i <= 1
    return "Game_" + num.to_i.to_s + ".rxdata"
  end

  def self.current_original_filename
    return original_filename_for_number(save_number)
  end

  def self.save_path(filename = nil)
    filename = current_original_filename if !filename
    return RTP.getSaveFileName(filename)
  rescue Exception
    return filename.to_s
  end

  def self.backup_dir
    base = RTP.getSaveFolder rescue "."
    return base.gsub(/[\/\\]$/, "") + "/" + BACKUP_DIR_NAME
  rescue Exception
    return BACKUP_DIR_NAME
  end

  def self.ensure_backup_dir
    dir = backup_dir
    Dir.mkdir(dir) if !FileTest.directory?(dir)
    return dir
  rescue Exception
    return backup_dir
  end

  def self.description_path(path)
    return path.to_s + ".description.txt"
  rescue Exception
    return "description.txt"
  end

  def self.location_image_path(path)
    return path.to_s + ".location.png"
  rescue Exception
    return ""
  end

  def self.capture_script_path
    return File.expand_path("multiplayer/save-manager/SebiCaptureWindow.ps1")
  rescue Exception
    return "multiplayer/save-manager/SebiCaptureWindow.ps1"
  end

  def self.preview_json_path(path)
    return path.to_s + ".preview.json"
  rescue Exception
    return ""
  end

  def self.clean_description(text)
    value = text.to_s.gsub(/\r|\n/, " ").strip
    value = value[0, 160] if value.length > 160
    return value
  rescue Exception
    return ""
  end

  def self.read_description(path)
    meta = description_path(path)
    return "" if !file_exists?(meta)
    text = ""
    File.open(meta, "rb") { |file| text = file.read(512).to_s }
    return clean_description(text)
  rescue Exception
    return ""
  end

  def self.write_description(path, description)
    meta = description_path(path)
    text = clean_description(description)
    tmp = meta + ".tmp"
    begin; File.delete(tmp); rescue Exception; end
    File.open(tmp, "wb") { |file| file.write(text) }
    begin; File.delete(meta); rescue Exception; end
    File.rename(tmp, meta)
    return true
  rescue Exception
    begin; File.delete(tmp); rescue Exception; end
    return false
  end

  def self.write_json_file(path, data)
    return false if !path || path.to_s == ""
    if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:atomic_write) && SebiSaveEditor.respond_to?(:json)
      SebiSaveEditor.atomic_write(path, SebiSaveEditor.json(data))
      return true
    end
    File.open(path, "wb") { |file| file.write(data.to_s) }
    return true
  rescue Exception
    return false
  end

  def self.save_bitmap_png(bitmap, path)
    return false if !bitmap || !path || path.to_s == ""
    if bitmap.respond_to?(:saveToPng)
      bitmap.saveToPng(path)
      return file_exists?(path)
    elsif bitmap.respond_to?(:save_to_png)
      bitmap.save_to_png(path)
      return file_exists?(path)
    end
    return false
  rescue Exception
    return false
  end

  def self.capture_location_image(path)
    image = location_image_path(path)
    script = capture_script_path
    return false if image.to_s == "" || !file_exists?(script)
    params = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " +
             quote_arg(script) + " -OutPath " + quote_arg(image)
    if defined?(Win32API)
      shell = Win32API.new("shell32", "ShellExecuteA", "LPPPPI", "I")
      result = shell.call(0, "open", "powershell.exe", params, nil, 0)
      return true if result && result.to_i > 32
    end
    system("cmd /c start \"\" powershell.exe " + params)
    return true
  rescue Exception
    return false
  end

  def self.quote_arg(value)
    return "\"" + value.to_s.gsub("\"", "") + "\""
  rescue Exception
    return "\"\""
  end

  def self.file_exists?(path)
    return safeExists?(path) if defined?(safeExists?)
    return FileTest.exist?(path)
  rescue Exception
    return false
  end

  def self.copy_file(source, target)
    return false if !file_exists?(source)
    tmp = target + ".tmp"
    begin; File.delete(tmp); rescue Exception; end
    File.open(source, "rb") do |input|
      File.open(tmp, "wb") do |output|
        loop do
          chunk = input.read(4096)
          break if !chunk
          output.write(chunk)
        end
      end
    end
    begin; File.delete(target); rescue Exception; end
    File.rename(tmp, target)
    return true
  rescue Exception
    begin; File.delete(tmp); rescue Exception; end
    return false
  end

  def self.timestamp_for_file
    return Time.now.strftime("%Y-%m-%d_%H-%M-%S")
  rescue Exception
    return now_i.to_s
  end

  def self.timestamp_for_label(path = nil)
    t = nil
    t = File.mtime(path) if path && file_exists?(path)
    t = Time.now if !t
    return t.strftime("%Y-%m-%d %H:%M:%S")
  rescue Exception
    return Time.now.to_s
  end

  def self.unique_backup_path_for_filename(filename, kind = "auto")
    dir = ensure_backup_dir
    base = File.basename(filename || current_original_filename, ".rxdata")
    suffix = timestamp_for_file
    suffix += "_" + kind.to_s if kind && kind.to_s != "" && kind.to_s != "auto"
    path = dir + "/" + base + "_" + suffix + ".rxdata"
    index = 1
    while file_exists?(path)
      path = dir + "/" + base + "_" + suffix + "_" + index.to_s + ".rxdata"
      index += 1
    end
    return path
  rescue Exception
    return "SebiLinkAutoBackup_" + now_i.to_s + ".rxdata"
  end

  def self.unique_backup_path(kind = "auto")
    return unique_backup_path_for_filename(current_original_filename, kind)
  end

  def self.slot_number_from_filename(filename)
    name = File.basename(filename.to_s)
    return 1 if name =~ /\AGame\.rxdata\z/i
    return $1.to_i if name =~ /\AGame_(\d+)\.rxdata\z/i
    return 1
  rescue Exception
    return 1
  end

  def self.original_filename_for_backup(path)
    name = File.basename(path.to_s)
    if name =~ /\A(Game(?:_\d+)?)_/
      return $1 + ".rxdata"
    end
    return current_original_filename
  rescue Exception
    return current_original_filename
  end

  def self.normal_save_file?(path)
    name = File.basename(path.to_s)
    return true if name =~ /\AGame(?:_\d+)?\.rxdata\z/i
    return false
  rescue Exception
    return false
  end

  def self.can_snapshot?(strict = true)
    return false if !$Trainer || !$game_player || !$game_map
    return false if !$game_system || !$PokemonSystem
    return false if !$game_switches || !$game_variables || !$game_self_switches || !$game_screen
    return false if !$MapFactory || !$PokemonGlobal || !$PokemonMap || !$PokemonBag || !$PokemonStorage
    if strict
      return false if $game_temp && $game_temp.in_battle
      return false if $game_temp && $game_temp.battle_calling
      return false if $game_temp && $game_temp.message_window_showing
      return false if $game_temp && $game_temp.player_transferring
      begin
        return false if pbMapInterpreterRunning?
      rescue Exception
      end
    end
    return true
  rescue Exception
    return false
  end

  def self.write_snapshot(path)
    return false if !can_snapshot?(false)
    tmp = path + ".tmp"
    begin; File.delete(tmp); rescue Exception; end
    $Trainer.metaID = $PokemonGlobal.playerID if $Trainer && $PokemonGlobal
    if $data_system.respond_to?("magic_number")
      $game_system.magic_number = $data_system.magic_number
    else
      $game_system.magic_number = $data_system.version_id
    end
    old_safesave = nil
    begin; old_safesave = $PokemonGlobal.safesave; rescue Exception; end
    $PokemonGlobal.safesave = false rescue nil
    File.open(tmp, "wb") do |file|
      Marshal.dump($Trainer, file)
      Marshal.dump(Graphics.frame_count, file)
      Marshal.dump($game_system, file)
      Marshal.dump($PokemonSystem, file)
      Marshal.dump($game_map.map_id, file)
      Marshal.dump($game_switches, file)
      Marshal.dump($game_variables, file)
      Marshal.dump($game_self_switches, file)
      Marshal.dump($game_screen, file)
      Marshal.dump($MapFactory, file)
      Marshal.dump($game_player, file)
      Marshal.dump($PokemonGlobal, file)
      Marshal.dump($PokemonMap, file)
      Marshal.dump($PokemonBag, file)
      Marshal.dump($PokemonStorage, file)
    end
    $PokemonGlobal.safesave = old_safesave rescue nil
    begin; File.delete(path); rescue Exception; end
    File.rename(tmp, path)
    return true
  rescue Exception
    $PokemonGlobal.safesave = old_safesave rescue nil
    begin; File.delete(tmp); rescue Exception; end
    return false
  end

  def self.prompt_description(default_value = "")
    return "" if !defined?(Kernel) || !Kernel.respond_to?(:pbMessageFreeText)
    value = Kernel.pbMessageFreeText(_INTL("Descripcion opcional para este respaldo."), default_value.to_s, false, 80)
    return clean_description(value)
  rescue Exception
    return ""
  end

  def self.create_backup(kind = "auto", show_message = false, description = nil)
    return [false, _INTL("No hay una partida cargada para respaldar.")] if !can_snapshot?(false)
    description = prompt_description("") if description == nil && show_message && kind.to_s == "manual"
    path = unique_backup_path(kind)
    if write_snapshot(path)
      write_live_preview_assets(path, true)
      write_description(path, description) if description && description.to_s != ""
      @last_message = _INTL("Respaldo creado: {1}", File.basename(path))
      return [true, @last_message]
    end
    return [false, _INTL("No se pudo crear el respaldo automatico.")]
  rescue Exception
    return [false, _INTL("No se pudo crear el respaldo automatico.")]
  end

  def self.validate_backup(path)
    return false if !file_exists?(path)
    File.open(path, "rb") do |file|
      trainer = Marshal.load(file)
      framecount = Marshal.load(file)
      game_system = Marshal.load(file)
      pokemon_system = Marshal.load(file)
      mapid = Marshal.load(file)
      return false if !trainer.is_a?(PokeBattle_Trainer)
      return false if !framecount.is_a?(Numeric)
      return false if !game_system.is_a?(Game_System)
      return false if !pokemon_system.is_a?(PokemonSystem)
      return false if !mapid.is_a?(Numeric)
    end
    return true
  rescue Exception
    return false
  end

  def self.load_save_sections(path)
    data = {}
    File.open(path, "rb") do |file|
      data["trainer"] = Marshal.load(file)
      data["frame"] = Marshal.load(file)
      data["gameSystem"] = Marshal.load(file)
      data["pokemonSystem"] = Marshal.load(file)
      data["mapId"] = Marshal.load(file)
      data["switches"] = Marshal.load(file)
      data["variables"] = Marshal.load(file)
      data["selfSwitches"] = Marshal.load(file)
      data["screen"] = Marshal.load(file)
      data["mapFactory"] = Marshal.load(file)
      data["player"] = Marshal.load(file)
      data["global"] = Marshal.load(file)
      data["pokemonMap"] = Marshal.load(file)
      data["bag"] = Marshal.load(file)
      data["storage"] = Marshal.load(file)
    end
    return data
  rescue Exception
    return nil
  end

  def self.preview_pokemon_data(pokemon, loc, index, box, slot)
    return nil if !pokemon
    species = 0
    begin; species = pokemon.species.to_i; rescue Exception; end
    return {
      "loc" => loc.to_s,
      "index" => index.to_i,
      "box" => box.to_i,
      "slot" => slot.to_i,
      "species" => species,
      "name" => (pokemon.name.to_s rescue ""),
      "level" => (pokemon.level.to_i rescue 0),
      "gender" => (pokemon.gender.to_i rescue 2),
      "shiny" => ((pokemon.respond_to?(:isShiny?) && pokemon.isShiny?) || (pokemon.respond_to?(:shiny?) && pokemon.shiny?)) ? true : false,
      "isEgg" => ((pokemon.respond_to?(:isEgg?) && pokemon.isEgg?) ? true : false)
    }
  rescue Exception
    return nil
  end

  def self.preview_data_for_path(path)
    sections = load_save_sections(path)
    return nil if !sections
    trainer = sections["trainer"]
    storage = sections["storage"]
    player = sections["player"]
    map_id = sections["mapId"].to_i
    party = []
    begin
      for i in 0...trainer.party.length
        data = preview_pokemon_data(trainer.party[i], "party", i, -1, -1)
        party.push(data) if data
      end
    rescue Exception
    end
    current_box = 0
    box_name = ""
    box_length = 30
    box_pokemon = []
    boxes = []
    begin
      current_box = storage.currentBox.to_i if storage.respond_to?(:currentBox)
      current_box = 0 if current_box < 0
      source_boxes = storage.respond_to?(:boxes) ? storage.boxes : []
      max_boxes = source_boxes.length rescue 0
      max_boxes = storage.maxBoxes.to_i if storage.respond_to?(:maxBoxes) && storage.maxBoxes.to_i > max_boxes
      max_boxes = 1 if max_boxes <= 0
      for box_index in 0...max_boxes
        box = storage[box_index] rescue nil
        box = source_boxes[box_index] if !box && source_boxes
        next if !box
        this_name = box.name.to_s rescue ("Caja " + (box_index + 1).to_s)
        this_length = box.length.to_i rescue 30
        this_pokemon = []
        for slot in 0...this_length
          data = preview_pokemon_data(box[slot], "box", -1, box_index, slot)
          this_pokemon.push(data) if data
        end
        boxes.push({
          "index" => box_index,
          "name" => this_name,
          "length" => this_length,
          "pokemon" => this_pokemon
        })
        next if box_index != current_box
        box_name = box.name.to_s rescue ("Caja " + (current_box + 1).to_s)
        box_length = box.length.to_i rescue 30
        box_pokemon = this_pokemon
      end
    rescue Exception
    end
    image = location_image_path(path)
    return {
      "path" => path.to_s,
      "generatedAt" => Time.now.to_s,
      "locationImage" => file_exists?(image) ? image : "",
      "trainer" => {
        "name" => (trainer.name.to_s rescue ""),
        "money" => (trainer.money.to_i rescue 0),
        "badges" => (trainer.numbadges.to_i rescue 0)
      },
      "map" => {
        "id" => map_id,
        "name" => (pbGetMapNameFromId(map_id).to_s rescue "")
      },
      "position" => {
        "x" => (player.x.to_i rescue 0),
        "y" => (player.y.to_i rescue 0),
        "direction" => (player.direction.to_i rescue 0)
      },
      "party" => party,
      "storage" => {
        "currentBox" => current_box,
        "boxName" => box_name,
        "length" => box_length,
        "pokemon" => box_pokemon,
        "boxes" => boxes
      }
    }
  rescue Exception
    return nil
  end

  def self.live_preview_data(path)
    return nil if !$Trainer
    party = []
    begin
      for i in 0...$Trainer.party.length
        data = preview_pokemon_data($Trainer.party[i], "party", i, -1, -1)
        party.push(data) if data
      end
    rescue Exception
    end
    current_box = 0
    box_name = ""
    box_length = 30
    box_pokemon = []
    boxes = []
    begin
      storage = $PokemonStorage
      if storage
        current_box = storage.currentBox.to_i if storage.respond_to?(:currentBox)
        current_box = 0 if current_box < 0
        source_boxes = storage.respond_to?(:boxes) ? storage.boxes : []
        max_boxes = source_boxes.length rescue 0
        max_boxes = storage.maxBoxes.to_i if storage.respond_to?(:maxBoxes) && storage.maxBoxes.to_i > max_boxes
        max_boxes = 1 if max_boxes <= 0
        for box_index in 0...max_boxes
          box = storage[box_index] rescue nil
          box = source_boxes[box_index] if !box && source_boxes
          next if !box
          this_name = box.name.to_s rescue ("Caja " + (box_index + 1).to_s)
          this_length = box.length.to_i rescue 30
          this_pokemon = []
          for slot in 0...this_length
            data = preview_pokemon_data(box[slot], "box", -1, box_index, slot)
            this_pokemon.push(data) if data
          end
          boxes.push({
            "index" => box_index,
            "name" => this_name,
            "length" => this_length,
            "pokemon" => this_pokemon
          })
          next if box_index != current_box
          box_name = box.name.to_s rescue ("Caja " + (current_box + 1).to_s)
          box_length = box.length.to_i rescue 30
          box_pokemon = this_pokemon
        end
      end
    rescue Exception
    end
    map_id = 0
    begin; map_id = $game_map.map_id.to_i if $game_map; rescue Exception; end
    image = location_image_path(path)
    return {
      "path" => path.to_s,
      "generatedAt" => Time.now.to_s,
      "locationImage" => file_exists?(image) ? image : "",
      "trainer" => {
        "name" => ($Trainer.name.to_s rescue ""),
        "money" => ($Trainer.money.to_i rescue 0),
        "badges" => ($Trainer.numbadges.to_i rescue 0)
      },
      "map" => {
        "id" => map_id,
        "name" => (pbGetMapNameFromId(map_id).to_s rescue "")
      },
      "position" => {
        "x" => ($game_player.x.to_i rescue 0),
        "y" => ($game_player.y.to_i rescue 0),
        "direction" => ($game_player.direction.to_i rescue 0)
      },
      "party" => party,
      "storage" => {
        "currentBox" => current_box,
        "boxName" => box_name,
        "length" => box_length,
        "pokemon" => box_pokemon,
        "boxes" => boxes
      }
    }
  rescue Exception
    return nil
  end

  def self.write_preview_json(path)
    data = preview_data_for_path(path)
    return false if !data
    data["locationImage"] = location_image_path(path) if file_exists?(location_image_path(path))
    return write_json_file(preview_json_path(path), data)
  rescue Exception
    return false
  end

  def self.write_live_preview_assets(path, capture = true)
    capture_location_image(path) if capture
    data = live_preview_data(path)
    return false if !data
    image = location_image_path(path)
    data["locationImage"] = image if capture || file_exists?(image)
    return write_json_file(preview_json_path(path), data)
  rescue Exception
    return false
  end

  def self.backup_summary(path)
    info = describe_save_file(path, "backup")
    original = info["original"].to_s
    label = original + " | " + info["timestamp"].to_s
    label += " | " + info["trainer"].to_s if info["trainer"] && info["trainer"].to_s != ""
    label += " | " + info["map"].to_s if info["map"] && info["map"].to_s != ""
    label += " | " + info["description"].to_s if info["description"] && info["description"].to_s != ""
    return label
  rescue Exception
    return File.basename(path)
  end

  def self.describe_save_file(path, type = "backup")
    trainer_name = "?"
    map_name = ""
    map_id = 0
    valid = false
    begin
      File.open(path, "rb") do |file|
        trainer = Marshal.load(file)
        Marshal.load(file)
        Marshal.load(file)
        Marshal.load(file)
        map_id = Marshal.load(file).to_i
        trainer_name = trainer.name.to_s if trainer && trainer.respond_to?(:name)
        map_name = pbGetMapNameFromId(map_id).to_s rescue ""
        valid = true
      end
    rescue Exception
    end
    original = type.to_s == "backup" ? original_filename_for_backup(path) : File.basename(path)
    slot = slot_number_from_filename(original)
    return {
      "type" => type.to_s,
      "path" => path.to_s,
      "name" => File.basename(path.to_s),
      "original" => original,
      "slot" => slot,
      "timestamp" => timestamp_for_label(path),
      "mtime" => (File.mtime(path).to_i rescue 0),
      "trainer" => trainer_name,
      "map" => map_name,
      "mapId" => map_id,
      "description" => read_description(path),
      "locationImage" => (file_exists?(location_image_path(path)) ? location_image_path(path) : ""),
      "previewPath" => preview_json_path(path),
      "valid" => valid ? true : false
    }
  rescue Exception
    return {
      "type" => type.to_s,
      "path" => path.to_s,
      "name" => File.basename(path.to_s),
      "original" => File.basename(path.to_s),
      "slot" => 1,
      "timestamp" => timestamp_for_label(path),
      "mtime" => 0,
      "trainer" => "?",
      "map" => "",
      "mapId" => 0,
      "description" => read_description(path),
      "locationImage" => (file_exists?(location_image_path(path)) ? location_image_path(path) : ""),
      "previewPath" => preview_json_path(path),
      "valid" => false
    }
  end

  def self.describe_save_file_fast(path, type = "backup")
    original = type.to_s == "backup" ? original_filename_for_backup(path) : File.basename(path)
    slot = slot_number_from_filename(original)
    return {
      "type" => type.to_s,
      "path" => path.to_s,
      "name" => File.basename(path.to_s),
      "original" => original,
      "slot" => slot,
      "timestamp" => timestamp_for_label(path),
      "mtime" => (File.mtime(path).to_i rescue 0),
      "trainer" => "",
      "map" => "",
      "mapId" => 0,
      "description" => read_description(path),
      "locationImage" => (file_exists?(location_image_path(path)) ? location_image_path(path) : ""),
      "previewPath" => preview_json_path(path),
      "valid" => file_exists?(path) ? true : false
    }
  rescue Exception
    return describe_save_file(path, type)
  end

  def self.list_backups
    dir = ensure_backup_dir
    ret = []
    for name in Dir.entries(dir)
      next if name == "." || name == ".."
      next if name[/\.tmp$/i]
      next if !name[/\.rxdata$/i]
      path = dir + "/" + name
      next if !file_exists?(path)
      mtime = File.mtime(path) rescue Time.at(0)
      ret.push({ :path => path, :name => name, :mtime => mtime })
    end
    ret.sort! { |a, b| b[:mtime] <=> a[:mtime] }
    return ret
  rescue Exception
    return []
  end

  def self.restore_backup(path)
    return [false, _INTL("Ese respaldo ya no existe.")] if !file_exists?(path)
    return [false, _INTL("Ese respaldo parece corrupto o incompatible.")] if !validate_backup(path)
    target_filename = original_filename_for_backup(path)
    target = save_path(target_filename)
    if file_exists?(target)
      before = unique_backup_path_for_filename(target_filename, "before-load")
      copy_file(target, before)
      write_description(before, _INTL("Respaldo automatico antes de cargar otra partida."))
    elsif can_snapshot?(false)
      create_backup("before-load", false)
    end
    if copy_file(path, target)
      pbStoredLastPlayed(slot_number_from_filename(target_filename), nil) if defined?(pbStoredLastPlayed)
      return [true, _INTL("Respaldo restaurado como {1}.", target_filename)]
    end
    return [false, _INTL("No se pudo reemplazar la partida actual.")]
  rescue Exception
    return [false, _INTL("No se pudo restaurar el respaldo.")]
  end

  def self.load_normal_save(path)
    return [false, _INTL("Esa partida ya no existe.")] if !file_exists?(path)
    return [false, _INTL("Esa partida parece corrupta o incompatible.")] if !validate_backup(path)
    filename = File.basename(path.to_s)
    pbStoredLastPlayed(slot_number_from_filename(filename), nil) if defined?(pbStoredLastPlayed)
    return [true, _INTL("Partida seleccionada: {1}.", filename)]
  rescue Exception
    return [false, _INTL("No se pudo cargar esa partida.")]
  end

  def self.restore_entry(path)
    return [false, _INTL("No se encontro la partida elegida.")] if !file_exists?(path)
    if normal_save_file?(path) && File.dirname(path.to_s).gsub("\\", "/") != backup_dir.gsub("\\", "/")
      return load_normal_save(path)
    end
    return restore_backup(path)
  end

  def self.update
    if !@next_backup_at
      @next_backup_at = now_i + INTERVAL_SECONDS
      return
    end
    return if now_i < @next_backup_at
    return if !can_snapshot?(true)
    ok, msg = create_backup("auto", false)
    @next_backup_at = now_i + INTERVAL_SECONDS
    SebiVisualMultiplayer.log(msg) if defined?(SebiVisualMultiplayer) && msg
  rescue Exception
    @next_backup_at = now_i + 60
  end

  def self.open_load_menu
    if defined?(SebiSaveManager)
      SebiSaveManager.open_window
      return :window_opened
    end
    backups = list_backups
    if backups.length == 0
      Kernel.pbMessage(_INTL("No hay respaldos automaticos todavia."))
      return nil
    end
    shown = backups
    commands = []
    for backup in shown
      commands.push(backup_summary(backup[:path]))
    end
    commands.push(_INTL("Salir"))
    cmd = Kernel.pbMessage(_INTL("Elige respaldo para cargar. Se reemplazara la partida actual, pero el respaldo elegido no se borrara."), commands, commands.length)
    return nil if cmd < 0 || cmd >= shown.length
    backup = shown[cmd]
    if !Kernel.pbConfirmMessageSerious(_INTL("Reemplazar {1} por este respaldo?", current_original_filename))
      return nil
    end
    ok, msg = restore_backup(backup[:path])
    Kernel.pbMessage(msg)
    if ok
      Kernel.pbMessage(_INTL("Reiniciando el juego para cargar la partida restaurada."))
      if defined?(SebiSaveManager) && SebiSaveManager.respond_to?(:request_game_restart_after_load)
        SebiSaveManager.request_game_restart_after_load
      elsif defined?(SebiSaveManager) && SebiSaveManager.respond_to?(:request_return_to_title)
        SebiSaveManager.request_return_to_title
      else
        $game_temp.to_title = true if $game_temp
      end
      return :restored
    end
    return nil
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir la lista de respaldos."))
    return nil
  end

  def self.open_menu
    loop do
      commands = [
        _INTL("Crear respaldo ahora"),
        _INTL("Cargar partida/respaldos"),
        _INTL("Ayuda"),
        _INTL("Salir")
      ]
      cmd = Kernel.pbMessage(_INTL("Guardados automaticos\nCada 5 minutos se crea un respaldo."), commands, commands.length)
      case cmd
      when 0
        ok, msg = create_backup("manual", true)
        Kernel.pbMessage(msg)
      when 1
        result = open_load_menu
        return result if result == :restored || result == :window_opened
      when 2
        Kernel.pbMessage(_INTL("La carga de partidas se abre en una ventana externa. Ahi puedes cargar partidas normales, respaldos y configurar partidas rapidas. Los respaldos se guardan dentro de {1}.", BACKUP_DIR_NAME))
      else
        break
      end
    end
    return nil
  end
end

module SebiSaveManager
  MANAGER_KEY = 0x00
  QUICK_WINDOW_KEY = 0x77
  COMMAND_POLL_FRAMES = 15
  OPEN_COOLDOWN_FRAMES = 20
  @last_command_poll_frame = -9999
  @last_open_frame = -9999
  @processing_command = false
  @quick_key_pressed = {}
  @quick_window_key_pressed = false
  @get_async_key_state = nil
  @pending_title_reload_frames = 0
  @pending_game_restart_frames = 0

  def self.manager_path
    return File.expand_path("multiplayer/save-manager/SebiSaveManager.ps1")
  rescue Exception
    return "multiplayer/save-manager/SebiSaveManager.ps1"
  end

  def self.runtime_dir
    return SebiLinkPaths.runtime_dir("save-manager") if defined?(SebiLinkPaths)
    return File.expand_path("multiplayer/save-manager/runtime")
  rescue Exception
    return "SebiLinkConfig/save-manager/runtime"
  end

  def self.command_path
    return File.join(runtime_dir, "commands.txt")
  end

  def self.result_path
    return File.join(runtime_dir, "last_result.json")
  end

  def self.index_path
    return File.join(runtime_dir, "index.json")
  end

  def self.preview_path
    return File.join(runtime_dir, "selected_preview.json")
  end

  def self.ensure_dir(path)
    if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:ensure_dir)
      SebiSaveEditor.ensure_dir(path)
      return
    end
    path = path.to_s.gsub("\\", "/")
    parts = path.split("/")
    current = ""
    for part in parts
      next if part == ""
      if current == ""
        current = part
      else
        current += "/" + part
      end
      next if part =~ /\A[A-Za-z]:\z/
      Dir.mkdir(current) if !FileTest.directory?(current)
    end
  rescue Exception
  end

  def self.atomic_write(path, text)
    if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:atomic_write)
      SebiSaveEditor.atomic_write(path, text)
      return
    end
    ensure_dir(File.dirname(path))
    File.open(path, "wb") { |file| file.write(text.to_s) }
  rescue Exception
  end

  def self.json(value)
    return SebiSaveEditor.json(value) if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:json)
    text = value.to_s
    text = text.gsub(/\\/) { "\\\\" }
    text = text.gsub(/"/) { "\\\"" }
    text = text.gsub(/\r/) { "\\r" }
    text = text.gsub(/\n/) { "\\n" }
    text = text.gsub(/\t/) { "\\t" }
    return "\"" + text + "\""
  rescue Exception
    return "\"\""
  end

  def self.write_result(seq, ok, message)
    atomic_write(result_path, json({
      "seq" => seq.to_s,
      "ok" => ok ? true : false,
      "message" => message.to_s,
      "time" => Time.now.to_s
    }))
  rescue Exception
  end

  def self.parse_command(line)
    return SebiSaveEditor.parse_command(line) if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:parse_command)
    return nil
  rescue Exception
    return nil
  end

  def self.save_folder
    return RTP.getSaveFolder rescue "."
  end

  def self.normal_save_paths
    dir = save_folder
    ret = []
    for name in Dir.entries(dir)
      next if name == "." || name == ".."
      next if !(name =~ /\AGame(?:_\d+)?\.rxdata\z/i)
      path = dir.gsub(/[\/\\]$/, "") + "/" + name
      ret.push(path) if SebiAutoBackups.file_exists?(path)
    end
    ret.sort! { |a, b| SebiAutoBackups.slot_number_from_filename(File.basename(a)) <=> SebiAutoBackups.slot_number_from_filename(File.basename(b)) }
    return ret
  rescue Exception
    return []
  end

  def self.quick_path_key(slot)
    return "quick_save_slot_" + slot.to_i.to_s + "_path"
  end

  def self.quick_key_key(slot)
    return "quick_save_slot_" + slot.to_i.to_s + "_key"
  end

  def self.quick_slot_path(slot)
    return "" if !defined?(SebiLinkFileConfig)
    return SebiLinkFileConfig.get(quick_path_key(slot), "").to_s
  rescue Exception
    return ""
  end

  def self.quick_slot_key(slot)
    return 0 if !defined?(SebiLinkFileConfig)
    return SebiLinkFileConfig.get_int(quick_key_key(slot), 0)
  rescue Exception
    return 0
  end

  def self.quick_key_name(key)
    key = key.to_i
    return _INTL("Sin tecla") if key == 0
    return SebiExtraControls.key_name(key) if defined?(SebiExtraControls)
    return Keys.getKeyName(key) if defined?(Keys) && Keys.respond_to?(:getKeyName)
    return key.to_s
  rescue Exception
    return key.to_s
  end

  def self.item_label_for_path(path, items = nil)
    items ||= collect_items
    for item in items
      return item["label"].to_s if item["path"].to_s == path.to_s
    end
    return File.basename(path.to_s)
  rescue Exception
    return File.basename(path.to_s)
  end

  def self.collect_items
    items = []
    for path in normal_save_paths
      info = SebiAutoBackups.describe_save_file_fast(path, "save")
      info["label"] = _INTL("Partida {1} | {2}", info["slot"], info["timestamp"])
      items.push(info)
    end
    for backup in SebiAutoBackups.list_backups
      info = SebiAutoBackups.describe_save_file_fast(backup[:path], "backup")
      info["label"] = _INTL("Respaldo de partida {1} | {2}", info["slot"], info["timestamp"])
      items.push(info)
    end
    return items
  rescue Exception
    return []
  end

  def self.collect_quick_slots(items = nil)
    items ||= collect_items
    slots = []
    for slot in 1..9
      path = quick_slot_path(slot)
      key = quick_slot_key(slot)
      exists = path != "" && SebiAutoBackups.file_exists?(path)
      slots.push({
        "slot" => slot,
        "path" => path,
        "exists" => exists ? true : false,
        "key" => key,
        "keyName" => quick_key_name(key),
        "label" => path == "" ? "" : item_label_for_path(path, items)
      })
    end
    return slots
  rescue Exception
    return []
  end

  def self.export_index
    if defined?(SebiLinkPaths)
      SebiLinkPaths.migrate_runtime_dir(File.expand_path("multiplayer/save-manager/runtime"), runtime_dir)
    end
    ensure_dir(runtime_dir)
    items = collect_items
    data = {
      "generatedAt" => Time.now.to_s,
      "saveFolder" => save_folder,
      "backupFolder" => SebiAutoBackups.backup_dir,
      "items" => items,
      "quickSlots" => collect_quick_slots(items)
    }
    atomic_write(index_path, json(data))
    return true
  rescue Exception
    return false
  end

  def self.quote_arg(value)
    return "\"" + value.to_s.gsub("\"", "") + "\""
  rescue Exception
    return "\"\""
  end

  def self.game_exe_path
    path = File.expand_path("Game.exe") rescue "Game.exe"
    return path if FileTest.exist?(path)
    return "Game.exe"
  rescue Exception
    return "Game.exe"
  end

  def self.open_powershell_script(path, extra_params = nil)
    params = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " + quote_arg(path)
    params += " " + extra_params.to_s if extra_params && extra_params.to_s != ""
    if defined?(Win32API)
      shell = Win32API.new("shell32", "ShellExecuteA", "LPPPPI", "I")
      result = shell.call(0, "open", "powershell.exe", params, nil, 0)
      return true if result && result.to_i > 32
    end
    system("cmd /c start \"\" powershell.exe " + params)
    return true
  rescue Exception
    return false
  end

  def self.open_window(quick_tab = false)
    path = manager_path
    export_index
    if !FileTest.exist?(path)
      Kernel.pbMessage(_INTL("No se encontro la ventana de partidas SebiLink."))
      return false
    end
    if !open_powershell_script(path, quick_tab ? "-QuickTab" : nil)
      Kernel.pbMessage(_INTL("No se pudo abrir la ventana de partidas SebiLink."))
      return false
    end
    return true
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir la ventana de partidas SebiLink.")) rescue nil
    return false
  end

  def self.open_quick_window
    return open_window(false)
  rescue Exception
    return false
  end

  def self.safe_to_restore?
    return false if !$Trainer
    if $game_temp
      return false if $game_temp.in_battle
      return false if $game_temp.battle_calling
      return false if $game_temp.message_window_showing
      return false if $game_temp.player_transferring
    end
    begin
      return false if pbMapInterpreterRunning?
    rescue Exception
    end
    return true
  rescue Exception
    return false
  end

  def self.delete_runtime_file(path)
    begin
      File.delete(path) if path && FileTest.exist?(path)
    rescue Exception
    end
  end

  def self.reset_for_save_change
    @processing_command = false
    @quick_key_pressed = {}
    @quick_window_key_pressed = false
    delete_runtime_file(command_path)
    delete_runtime_file(result_path)
  rescue Exception
  end

  def self.reset_windows_after_restore
    reset_for_save_change
    SebiSaveEditor.reset_for_save_change if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:reset_for_save_change)
    SebiLinkHub.reset_for_save_change if defined?(SebiLinkHub) && SebiLinkHub.respond_to?(:reset_for_save_change)
  rescue Exception
  end

  def self.scene_title?
    return false if !defined?(Scene_Title) || !$scene
    return $scene.is_a?(Scene_Title)
  rescue Exception
    return false
  end

  def self.force_return_to_title
    begin
      $game_temp.to_title = true if $game_temp
    rescue Exception
    end
    begin
      if defined?(Scene_Title) && !scene_title?
        $scene = Scene_Title.new
        return true
      end
      return true if scene_title?
    rescue Exception
    end
    return false
  end

  def self.request_return_to_title
    @pending_title_reload_frames = 30
    force_return_to_title
  rescue Exception
  end

  def self.handle_pending_return_to_title
    return if @pending_title_reload_frames.to_i <= 0
    if scene_title?
      @pending_title_reload_frames = 0
      return
    end
    force_return_to_title
    @pending_title_reload_frames -= 1
  rescue Exception
    @pending_title_reload_frames = 0
  end

  def self.restart_game_process
    path = game_exe_path
    return false if !FileTest.exist?(path)
    cwd = File.dirname(path)
    if defined?(Win32API)
      shell = Win32API.new("shell32", "ShellExecuteA", "LPPPPI", "I")
      result = shell.call(0, "open", path, nil, cwd, 1)
      return true if result && result.to_i > 32
    end
    system("cmd /c start \"\" " + quote_arg(path))
    return true
  rescue Exception
    return false
  end

  def self.request_game_restart_after_load
    @pending_game_restart_frames = 3
  rescue Exception
  end

  def self.handle_pending_game_restart
    return false if @pending_game_restart_frames.to_i <= 0
    if restart_game_process
      @pending_game_restart_frames = 0
      Kernel.exit
      return true
    end
    @pending_game_restart_frames -= 1
    request_return_to_title if @pending_game_restart_frames.to_i <= 0
    return false
  rescue SystemExit
    raise
  rescue Exception
    @pending_game_restart_frames = 0
    request_return_to_title
    return false
  end

  def self.restore_path(path)
    backup_current = @backup_current_before_restore ? true : false
    @backup_current_before_restore = false
    return [false, _INTL("No se puede cargar ahora mismo. Cierra combates, mensajes, eventos o transiciones.")] if !safe_to_restore?
    SebiAutoBackups.create_backup("before-load-current", false) if backup_current
    ok, msg = SebiAutoBackups.restore_entry(path)
    if ok
      export_index
      reset_windows_after_restore
      request_game_restart_after_load
      return [true, msg.to_s + " " + _INTL("Reiniciando el juego para cargarla.")]
    end
    return [false, msg]
  rescue Exception
    @backup_current_before_restore = false
    return [false, _INTL("No se pudo cargar esa partida.")]
  end

  def self.export_preview(path)
    return [false, _INTL("No se encontro la partida elegida.")] if !SebiAutoBackups.file_exists?(path)
    sidecar = SebiAutoBackups.preview_json_path(path)
    return [false, _INTL("Esa partida no tiene datos de preview guardados todavia.")] if !SebiAutoBackups.file_exists?(sidecar)
    return [true, _INTL("Datos de partida disponibles.")]
  rescue Exception
    return [false, _INTL("No se pudo exportar la preview de esa partida.")]
  end

  def self.edit_path(path)
    return [false, _INTL("No se encontro la partida elegida.")] if !SebiAutoBackups.file_exists?(path)
    return [false, _INTL("SebiHeX no esta disponible.")] if !defined?(SebiSaveEditor) || !SebiSaveEditor.respond_to?(:open_external_file)
    return SebiSaveEditor.open_external_file(path)
  rescue Exception
    return [false, _INTL("No se pudo abrir esa partida para editar.")]
  end

  def self.assign_quick_slot(slot, path)
    slot = slot.to_i
    return [false, _INTL("Slot rapido invalido.")] if slot < 1 || slot > 9
    return [false, _INTL("La partida elegida no existe.")] if !SebiAutoBackups.file_exists?(path)
    SebiLinkFileConfig.set(quick_path_key(slot), path.to_s) if defined?(SebiLinkFileConfig)
    export_index
    return [true, _INTL("Partida rapida {1} asignada.", slot)]
  rescue Exception
    return [false, _INTL("No se pudo asignar esa partida rapida.")]
  end

  def self.clear_quick_slot(slot)
    slot = slot.to_i
    return [false, _INTL("Slot rapido invalido.")] if slot < 1 || slot > 9
    if defined?(SebiLinkFileConfig)
      SebiLinkFileConfig.set(quick_path_key(slot), "")
      SebiLinkFileConfig.set(quick_key_key(slot), "0")
    end
    export_index
    return [true, _INTL("Partida rapida {1} limpiada.", slot)]
  rescue Exception
    return [false, _INTL("No se pudo limpiar esa partida rapida.")]
  end

  def self.move_quick_slot(slot, direction)
    slot = slot.to_i
    direction = direction.to_i
    target = slot + (direction < 0 ? -1 : 1)
    return [false, _INTL("Slot rapido invalido.")] if slot < 1 || slot > 9
    return [false, _INTL("No se puede mover mas.")] if target < 1 || target > 9
    path_a = quick_slot_path(slot)
    key_a = quick_slot_key(slot)
    path_b = quick_slot_path(target)
    key_b = quick_slot_key(target)
    if defined?(SebiLinkFileConfig)
      SebiLinkFileConfig.set(quick_path_key(slot), path_b.to_s)
      SebiLinkFileConfig.set(quick_key_key(slot), key_b.to_s)
      SebiLinkFileConfig.set(quick_path_key(target), path_a.to_s)
      SebiLinkFileConfig.set(quick_key_key(target), key_a.to_s)
    end
    export_index
    return [true, _INTL("Partida rapida {1} movida a {2}.", slot, target)]
  rescue Exception
    return [false, _INTL("No se pudo mover esa partida rapida.")]
  end

  def self.duplicate_quick_key?(slot, key)
    key = key.to_i
    return false if key == 0
    for other in 1..9
      next if other == slot.to_i
      return true if quick_slot_key(other) == key
    end
    return false
  rescue Exception
    return false
  end

  def self.reserved_sebilink_key?(key)
    key = key.to_i
    return false if key == 0
    reserved = [0x70, 0x74, QUICK_WINDOW_KEY]
    reserved.push(SebiSaveEditor::EDITOR_KEY) if defined?(SebiSaveEditor) && SebiSaveEditor.const_defined?(:EDITOR_KEY)
    reserved.push(SebiCheats::REPEL_TOGGLE_KEY) if defined?(SebiCheats) && SebiCheats.const_defined?(:REPEL_TOGGLE_KEY)
    reserved.push(SebiLinkHub::HUB_KEY) if defined?(SebiLinkHub) && SebiLinkHub.const_defined?(:HUB_KEY)
    if defined?(SebiExtraControls)
      reserved.push(SebiExtraControls.db_key) if SebiExtraControls.respond_to?(:db_key)
      reserved.push(SebiExtraControls.weakness_key) if SebiExtraControls.respond_to?(:weakness_key)
      reserved.push(SebiExtraControls.level_key) if SebiExtraControls.respond_to?(:level_key)
    end
    return reserved.include?(key)
  rescue Exception
    return false
  end

  def self.set_quick_key(slot, key)
    slot = slot.to_i
    key = key.to_i
    return [false, _INTL("Slot rapido invalido.")] if slot < 1 || slot > 9
    if key != 0 && defined?(SebiExtraControls) && SebiExtraControls.respond_to?(:reserved_gameplay_key?) && SebiExtraControls.reserved_gameplay_key?(key)
      return [false, _INTL("Esa tecla ya se usa para controles del juego. Elige una tecla libre.")]
    end
    return [false, _INTL("Esa tecla ya se usa por otra funcion SebiLink. Elige una tecla libre.")] if reserved_sebilink_key?(key)
    return [false, _INTL("Esa tecla ya esta usada por otra partida rapida.")] if duplicate_quick_key?(slot, key)
    SebiLinkFileConfig.set(quick_key_key(slot), key.to_s) if defined?(SebiLinkFileConfig)
    export_index
    return [true, _INTL("Tecla de partida rapida {1}: {2}.", slot, quick_key_name(key))]
  rescue Exception
    return [false, _INTL("No se pudo cambiar la tecla rapida.")]
  end

  def self.raw_key_pressed?(key)
    @get_async_key_state = Win32API.new("user32", "GetAsyncKeyState", "i", "i") if !@get_async_key_state && defined?(Win32API)
    return false if !@get_async_key_state
    return (@get_async_key_state.call(key.to_i) & 0x8000) != 0
  rescue Exception
    return false
  end

  def self.quick_key_triggered?(slot, key)
    key = key.to_i
    return false if key == 0
    triggered = false
    begin
      triggered = true if defined?(Input) && Input.respond_to?(:triggerex?) && Input.triggerex?(key)
    rescue Exception
    end
    pressed = raw_key_pressed?(key)
    old = @quick_key_pressed[slot.to_i] ? true : false
    triggered = true if pressed && !old
    @quick_key_pressed[slot.to_i] = pressed
    return triggered
  rescue Exception
    return false
  end

  def self.load_quick_slot(slot)
    slot = slot.to_i
    path = quick_slot_path(slot)
    return [false, _INTL("Partida rapida {1} no tiene partida asignada.", slot)] if path == ""
    return restore_path(path)
  rescue Exception
    return [false, _INTL("No se pudo cargar la partida rapida {1}.", slot)]
  end

  def self.handle_quick_hotkeys
    for slot in 1..9
      key = quick_slot_key(slot)
      next if reserved_sebilink_key?(key)
      next if !quick_key_triggered?(slot, key)
      ok, msg = load_quick_slot(slot)
      SebiVisualMultiplayer.log(msg) if defined?(SebiVisualMultiplayer) && msg
      break if ok
    end
  rescue Exception
  end

  def self.quick_window_key_triggered?
    triggered = false
    begin
      triggered = true if defined?(Input) && Input.respond_to?(:triggerex?) && Input.triggerex?(QUICK_WINDOW_KEY)
    rescue Exception
    end
    pressed = raw_key_pressed?(QUICK_WINDOW_KEY)
    triggered = true if pressed && !@quick_window_key_pressed
    @quick_window_key_pressed = pressed
    return triggered
  rescue Exception
    @quick_window_key_pressed = false
    return false
  end

  def self.quick_window_key_down?
    return raw_key_pressed?(QUICK_WINDOW_KEY)
  rescue Exception
    return false
  end

  def self.handle_shortcut
    return if !quick_window_key_triggered?
    frame = Graphics.frame_count rescue 0
    return if @last_open_frame && frame - @last_open_frame < OPEN_COOLDOWN_FRAMES
    @last_open_frame = frame
    open_quick_window
  rescue Exception
  end

  def self.run_command(command)
    args = command["args"] || {}
    case command["cmd"].to_s
    when "refresh_index"
      return [export_index, _INTL("Lista de partidas actualizada.")]
    when "restore_path"
      backup_value = args["backupCurrent"].to_s
      @backup_current_before_restore = (backup_value == "true" || backup_value == "1" || backup_value == "yes" || backup_value == "si")
      return restore_path(args["path"].to_s)
    when "export_preview"
      return export_preview(args["path"].to_s)
    when "edit_path"
      return edit_path(args["path"].to_s)
    when "create_backup"
      ok, msg = SebiAutoBackups.create_backup("manual", false, args["description"].to_s)
      export_index
      return [ok, msg]
    when "set_description"
      path = args["path"].to_s
      return [false, _INTL("Esa partida ya no existe.")] if !SebiAutoBackups.file_exists?(path)
      SebiAutoBackups.write_description(path, args["description"].to_s)
      export_index
      return [true, _INTL("Descripcion actualizada.")]
    when "assign_quick_slot"
      return assign_quick_slot(args["slot"].to_i, args["path"].to_s)
    when "clear_quick_slot"
      return clear_quick_slot(args["slot"].to_i)
    when "set_quick_key"
      return set_quick_key(args["slot"].to_i, args["key"].to_i)
    when "move_quick_slot"
      return move_quick_slot(args["slot"].to_i, args["direction"].to_i)
    when "load_quick_slot"
      backup_value = args["backupCurrent"].to_s
      @backup_current_before_restore = (backup_value == "true" || backup_value == "1" || backup_value == "yes" || backup_value == "si")
      return load_quick_slot(args["slot"].to_i)
    else
      return [false, _INTL("Comando de partidas desconocido: {1}", command["cmd"].to_s)]
    end
  rescue Exception
    return [false, _INTL("Error en gestor de partidas: {1}", $!.message.to_s)]
  end

  def self.process_commands
    path = command_path
    return if !FileTest.exist?(path)
    lines = []
    File.open(path, "rb") { |file| lines = file.readlines }
    begin; File.delete(path); rescue Exception; end
    for line in lines
      command = parse_command(line)
      next if !command || command["cmd"].to_s == ""
      ok, msg = run_command(command)
      write_result(command["seq"], ok, msg)
    end
  rescue Exception
  end

  def self.update
    return if handle_pending_game_restart
    handle_pending_return_to_title
    handle_shortcut
    handle_quick_hotkeys
    frame = Graphics.frame_count rescue 0
    return if @last_command_poll_frame && frame - @last_command_poll_frame < COMMAND_POLL_FRAMES
    @last_command_poll_frame = frame
    return if @processing_command
    @processing_command = true
    process_commands
    @processing_command = false
  rescue SystemExit
    raise
  rescue Exception
    @processing_command = false
  end
end

if defined?(PokemonSave)
  class PokemonSave
    unless method_defined?(:sebi_save_manager_pbSaveScreen_without_description)
      alias sebi_save_manager_pbSaveScreen_without_description pbSaveScreen

      def pbSaveScreen
        ret = sebi_save_manager_pbSaveScreen_without_description
        begin
          if defined?(SebiAutoBackups)
            SebiAutoBackups.write_live_preview_assets(SebiAutoBackups.save_path, true)
          end
        rescue Exception
        end
        return ret
      rescue Exception
        return ret
      end
    end
  end
end

module SebiBattleAdvisor
  def self.base_dir
    return File.expand_path("multiplayer/ai-codex")
  rescue Exception
    return "multiplayer/ai-codex"
  end

  def self.runtime_dir
    return SebiLinkPaths.runtime_dir("ai-codex") if defined?(SebiLinkPaths)
    return File.join(base_dir, "runtime")
  end

  def self.window_path
    return File.join(base_dir, "SebiBattleAdvisor.ps1")
  end

  def self.state_path
    return File.join(runtime_dir, "battle_state.json")
  end

  def self.team_state_path
    return File.join(runtime_dir, "team_state.json")
  end

  def self.last_battle_history_path
    return File.join(runtime_dir, "last_battle_history.json")
  end

  def self.pvp_ai_team_path
    return File.join(runtime_dir, "pvp_ai_team.txt")
  end

  def self.ensure_dir(path)
    if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:ensure_dir)
      SebiSaveEditor.ensure_dir(path)
      return
    end
    path = path.to_s.gsub("\\", "/")
    parts = path.split("/")
    current = ""
    for part in parts
      next if part == ""
      current = (current == "") ? part : current + "/" + part
      next if part =~ /\A[A-Za-z]:\z/
      Dir.mkdir(current) if !FileTest.directory?(current)
    end
  rescue Exception
  end

  def self.ensure_runtime
    if defined?(SebiLinkPaths)
      SebiLinkPaths.migrate_runtime_dir(File.join(base_dir, "runtime"), runtime_dir)
    end
    ensure_dir(runtime_dir)
  end

  def self.atomic_write(path, text)
    if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:atomic_write)
      SebiSaveEditor.atomic_write(path, text)
      return
    end
    ensure_dir(File.dirname(path))
    File.open(path, "wb") { |file| file.write(text.to_s) }
  rescue Exception
  end

  def self.json(value)
    return SebiSaveEditor.json(value) if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:json)
    return "null" if value == nil
    return "true" if value == true
    return "false" if value == false
    return value.to_s if value.is_a?(Numeric)
    if value.is_a?(Array)
      return "[" + value.collect { |item| json(item) }.join(",") + "]"
    end
    if value.is_a?(Hash)
      parts = []
      value.each { |key, item| parts.push(json_escape(key.to_s) + ":" + json(item)) }
      return "{" + parts.join(",") + "}"
    end
    return json_escape(value)
  rescue Exception
    return "null"
  end

  def self.json_escape(value)
    text = value.to_s
    text = text.gsub(/\\/) { "\\\\" }
    text = text.gsub(/"/) { "\\\"" }
    text = text.gsub(/\r/) { "\\r" }
    text = text.gsub(/\n/) { "\\n" }
    text = text.gsub(/\t/) { "\\t" }
    return "\"" + text + "\""
  rescue Exception
    return "\"\""
  end

  def self.safe(default_value = nil)
    return yield
  rescue Exception
    return default_value
  end

  def self.const_key(name)
    return name.is_a?(Symbol) ? name : name.to_s.to_sym
  end

  def self.name_from(mod_name, id)
    mod = Object.const_get(const_key(mod_name))
    name = safe("") { mod.getName(id.to_i).to_s }
    return name if name && name != ""
    return ""
  rescue Exception
    return ""
  end

  def self.type_name(type)
    name = name_from("PBTypes", type)
    return name if name && name != ""
    return "Ninguno" if type.to_i < 0
    return type.to_s
  rescue Exception
    return type.to_s
  end

  def self.status_name(status)
    status = status.to_i
    return "Normal" if status == 0
    name = name_from("PBStatuses", status)
    return name if name && name != ""
    return status.to_s
  rescue Exception
    return "Normal"
  end

  def self.weather_name(weather)
    weather = weather.to_i
    return "Ninguno" if weather == 0
    name = name_from("PBWeather", weather)
    return name if name && name != ""
    return weather.to_s
  rescue Exception
    return weather.to_s
  end

  def self.environment_name(environment)
    environment = environment.to_i
    return "Ninguno" if environment == 0
    name = name_from("PBEnvironment", environment)
    return name if name && name != ""
    return environment.to_s
  rescue Exception
    return environment.to_s
  end

  def self.trainer_data(trainer)
    if trainer.is_a?(Array)
      ret = []
      for item in trainer
        ret.push(trainer_data(item))
      end
      return ret
    end
    return nil if !trainer
    type = safe(0) { trainer.trainertype.to_i }
    return {
      "name" => safe("") { trainer.name.to_s },
      "id" => safe(0) { trainer.id.to_i },
      "trainerType" => type,
      "trainerTypeName" => type > 0 ? name_from("PBTrainers", type) : ""
    }
  rescue Exception
    return nil
  end

  def self.move_details(move, slot = nil)
    id = safe(0) { move.id.to_i }
    details = nil
    details = SebiMoveInfo.details(id) if defined?(SebiMoveInfo)
    details = {
      "id" => id,
      "name" => id > 0 ? name_from("PBMoves", id) : "",
      "type" => -1,
      "typeName" => "",
      "category" => -1,
      "categoryName" => "",
      "power" => 0,
      "accuracy" => 0,
      "pp" => 0,
      "description" => ""
    } if !details
    data = safe(nil) { PBMoveData.new(id) } if id > 0 && defined?(PBMoveData)
    details["slot"] = slot if slot != nil
    details["currentPp"] = safe(0) { move.pp.to_i }
    details["totalPp"] = safe(details["pp"].to_i) { move.totalpp.to_i }
    details["ppUp"] = safe(0) { move.ppup.to_i }
    details["function"] = safe(nil) { data.function }
    details["target"] = safe(nil) { data.target }
    details["priority"] = safe(0) { move.priority.to_i }
    details["typeName"] = type_name(details["type"]) if !details["typeName"] || details["typeName"] == ""
    return details
  rescue Exception
    return { "slot" => slot, "id" => id || 0, "name" => "", "currentPp" => 0, "totalPp" => 0 }
  end

  def self.move_effectiveness(battle, attacker_index, move)
    ret = []
    return ret if !battle || attacker_index == nil || !move || !defined?(SebiBattleEffectiveness)
    for target in battle.battlers
      next if !target || target.isFainted?
      opposing = safe(false) { battle.battlers[attacker_index].pbIsOpposing?(target.index) }
      next if !opposing
      result = SebiBattleEffectiveness.result_for_target(battle, attacker_index, move, target.index)
      mods = []
      label = ""
      if result
        label = result[:label].to_s rescue ""
        raw_mods = result[:mods] rescue []
        if raw_mods
          for mod in raw_mods
            mods.push(mod.to_i)
          end
        end
      end
      ret.push({
        "targetIndex" => target.index,
        "targetName" => safe("") { target.name.to_s },
        "label" => label,
        "mods" => mods
      })
    end
    return ret
  rescue Exception
    return ret || []
  end

  def self.stat_array(pokemon, key)
    source = safe([]) { pokemon.send(key) }
    ret = []
    for i in 0...6
      ret.push(safe(0) { source[i].to_i })
    end
    return ret
  rescue Exception
    return [0, 0, 0, 0, 0, 0]
  end

  def self.base_stats_for_pokemon(pokemon)
    return SebiSaveEditor.base_stats_for_pokemon(pokemon) if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:base_stats_for_pokemon)
    arr = safe(nil) { pokemon.baseStats }
    return [arr[0].to_i, arr[1].to_i, arr[2].to_i, arr[4].to_i, arr[5].to_i, arr[3].to_i] if arr && arr.length >= 6
    return [0, 0, 0, 0, 0, 0]
  rescue Exception
    return [0, 0, 0, 0, 0, 0]
  end

  def self.move_detail_by_id(move_id, level = nil)
    move_id = move_id.to_i
    detail = nil
    detail = SebiMoveInfo.details(move_id) if defined?(SebiMoveInfo)
    detail = {
      "id" => move_id,
      "name" => move_id > 0 ? name_from("PBMoves", move_id) : "",
      "type" => -1,
      "typeName" => "",
      "category" => -1,
      "categoryName" => "",
      "power" => 0,
      "accuracy" => 0,
      "pp" => 0,
      "description" => ""
    } if !detail
    detail["level"] = level.to_i if level != nil
    return detail
  rescue Exception
    ret = { "id" => move_id || 0, "name" => "" }
    ret["level"] = level.to_i if level != nil
    return ret
  end

  def self.level_up_moves_for(pokemon, max_level, min_level = nil)
    ret = []
    return ret if !pokemon || !pokemon.respond_to?(:getMoveList)
    max_level = max_level.to_i
    min_level = min_level.to_i if min_level != nil
    seen = {}
    list = safe([]) { pokemon.getMoveList }
    for entry in list
      next if !entry
      level = 0
      move_id = 0
      if entry.is_a?(Array)
        level = safe(0) { entry[0].to_i }
        move_id = safe(0) { entry[1].to_i }
      else
        move_id = safe(0) { entry.to_i }
      end
      next if move_id <= 0
      next if level > max_level
      next if min_level != nil && level <= min_level
      next if seen[move_id]
      ret.push(move_detail_by_id(move_id, level))
      seen[move_id] = true
    end
    return ret
  rescue Exception
    return []
  end

  def self.stats_for_level(pokemon, level)
    level = level.to_i
    return nil if !pokemon || level <= 0
    copy = safe(nil) { Marshal.load(Marshal.dump(pokemon)) }
    return nil if !copy
    copy.level = level if copy.respond_to?(:level=)
    copy.calcStats if copy.respond_to?(:calcStats)
    return {
      "level" => level,
      "hp" => safe(0) { copy.totalhp.to_i },
      "attack" => safe(0) { copy.attack.to_i },
      "defense" => safe(0) { copy.defense.to_i },
      "speed" => safe(0) { copy.speed.to_i },
      "spatk" => safe(0) { copy.spatk.to_i },
      "spdef" => safe(0) { copy.spdef.to_i }
    }
  rescue Exception
    return nil
  end

  def self.team_pokemon_data(pokemon, loc, index, box, slot, analysis_level)
    data = pokemon_data(pokemon, loc, index)
    return nil if !data
    current_level = data["level"].to_i
    analysis_level = [analysis_level.to_i, current_level].max
    data["box"] = box
    data["slot"] = slot
    data["analysisLevel"] = analysis_level
    data["learnableLevelMovesCurrent"] = level_up_moves_for(pokemon, current_level)
    data["learnableLevelMovesAtAnalysisLevel"] = level_up_moves_for(pokemon, analysis_level)
    data["newLevelMovesByAnalysisLevel"] = level_up_moves_for(pokemon, analysis_level, current_level)
    stats = stats_for_level(pokemon, analysis_level)
    data["statsAtAnalysisLevel"] = stats if stats
    return data
  rescue Exception
    return nil
  end

  def self.pokemon_data(pokemon, loc, index, battle = nil, battler_index = nil)
    return nil if !pokemon
    species = safe(0) { pokemon.species.to_i }
    item = safe(0) { pokemon.item.to_i }
    ability = safe(0) { pokemon.ability.to_i }
    nature = safe(0) { pokemon.nature.to_i }
    type1 = safe(-1) { pokemon.type1.to_i }
    type2 = safe(-1) { pokemon.type2.to_i }
    moves = []
    raw_moves = safe([]) { pokemon.moves }
    for i in 0...4
      move = raw_moves[i] rescue nil
      moves.push(move_details(move, i)) if move && safe(0) { move.id.to_i } > 0
    end
    return {
      "loc" => loc,
      "index" => index,
      "species" => species,
      "speciesName" => name_from("PBSpecies", species),
      "nickname" => safe("") { pokemon.name.to_s },
      "level" => safe(1) { pokemon.level.to_i },
      "hp" => safe(0) { pokemon.hp.to_i },
      "totalhp" => safe(0) { pokemon.totalhp.to_i },
      "hpPercent" => safe(0) { pokemon.totalhp.to_i > 0 ? ((pokemon.hp.to_f * 100.0) / pokemon.totalhp.to_f).round : 0 },
      "status" => safe(0) { pokemon.status.to_i },
      "statusName" => status_name(safe(0) { pokemon.status.to_i }),
      "statusCount" => safe(0) { pokemon.statusCount.to_i },
      "type1" => type1,
      "type1Name" => type_name(type1),
      "type2" => type2,
      "type2Name" => type_name(type2),
      "types" => [type_name(type1), type2 == type1 ? nil : type_name(type2)].compact,
      "item" => item,
      "itemName" => item > 0 ? name_from("PBItems", item) : "",
      "ability" => ability,
      "abilityName" => ability > 0 ? name_from("PBAbilities", ability) : "",
      "nature" => nature,
      "natureName" => name_from("PBNatures", nature),
      "gender" => safe(2) { pokemon.gender.to_i },
      "shiny" => safe(false) { pokemon.isShiny? ? true : false },
      "form" => safe(0) { pokemon.form.to_i },
      "happiness" => safe(0) { pokemon.happiness.to_i },
      "baseStats" => base_stats_for_pokemon(pokemon),
      "iv" => stat_array(pokemon, :iv),
      "ev" => stat_array(pokemon, :ev),
      "stats" => {
        "hp" => safe(0) { pokemon.totalhp.to_i },
        "attack" => safe(0) { pokemon.attack.to_i },
        "defense" => safe(0) { pokemon.defense.to_i },
        "speed" => safe(0) { pokemon.speed.to_i },
        "spatk" => safe(0) { pokemon.spatk.to_i },
        "spdef" => safe(0) { pokemon.spdef.to_i }
      },
      "moves" => moves,
      "isEgg" => safe(false) { pokemon.isEgg? ? true : false },
      "battleIndex" => battler_index
    }
  rescue Exception
    return nil
  end

  def self.party_data(party, loc)
    ret = []
    return ret if !party
    for i in 0...party.length
      data = pokemon_data(party[i], loc, i)
      ret.push(data) if data
    end
    return ret
  rescue Exception
    return ret || []
  end

  def self.effect_value(effect_source, name)
    return nil if !defined?(PBEffects) || !effect_source
    key = name.to_s.to_sym
    return nil if !PBEffects.const_defined?(key)
    id = PBEffects.const_get(key)
    value = effect_source[id] rescue nil
    return nil if value == nil || value == false || value == 0 || value == -1 || value == ""
    return value
  rescue Exception
    return nil
  end

  def self.effects_hash(effect_source, names)
    ret = {}
    for name in names
      value = effect_value(effect_source, name)
      ret[name] = value if value != nil
    end
    return ret
  rescue Exception
    return ret || {}
  end

  def self.active_battler_data(battle, battler)
    return nil if !battle || !battler || battler.isFainted?
    pokemon = safe(nil) { battler.pokemon }
    data = pokemon_data(pokemon, "active", battler.index, battle, battler.index)
    data = {} if !data
    active_moves = []
    moves = safe([]) { battler.moves }
    for i in 0...moves.length
      move = moves[i]
      next if !move || safe(0) { move.id.to_i } <= 0
      details = move_details(move, i)
      details["effectiveness"] = move_effectiveness(battle, battler.index, move)
      active_moves.push(details)
    end
    data["battlerIndex"] = battler.index
    data["partyIndex"] = safe(-1) { battler.pokemonIndex.to_i }
    data["side"] = safe(false) { battle.pbIsOpposing?(battler.index) } ? "rival" : "jugador"
    data["ownedByPlayer"] = safe(false) { battle.pbOwnedByPlayer?(battler.index) ? true : false }
    data["isOpposing"] = safe(false) { battle.pbIsOpposing?(battler.index) ? true : false }
    data["hp"] = safe(0) { battler.hp.to_i }
    data["totalhp"] = safe(0) { battler.totalhp.to_i }
    data["hpPercent"] = safe(0) { battler.totalhp.to_i > 0 ? ((battler.hp.to_f * 100.0) / battler.totalhp.to_f).round : 0 }
    data["status"] = safe(0) { battler.status.to_i }
    data["statusName"] = status_name(safe(0) { battler.status.to_i })
    data["statusCount"] = safe(0) { battler.statusCount.to_i }
    data["currentStats"] = {
      "attack" => safe(0) { battler.attack.to_i },
      "defense" => safe(0) { battler.defense.to_i },
      "speed" => safe(0) { battler.speed.to_i },
      "spatk" => safe(0) { battler.spatk.to_i },
      "spdef" => safe(0) { battler.spdef.to_i }
    }
    data["stages"] = {
      "attack" => safe(0) { battler.stages[PBStats::ATTACK].to_i },
      "defense" => safe(0) { battler.stages[PBStats::DEFENSE].to_i },
      "speed" => safe(0) { battler.stages[PBStats::SPEED].to_i },
      "spatk" => safe(0) { battler.stages[PBStats::SPATK].to_i },
      "spdef" => safe(0) { battler.stages[PBStats::SPDEF].to_i },
      "accuracy" => safe(0) { battler.stages[PBStats::ACCURACY].to_i },
      "evasion" => safe(0) { battler.stages[PBStats::EVASION].to_i }
    }
    data["moves"] = active_moves
    data["effects"] = effects_hash(safe(nil) { battler.effects }, [
      "Confusion", "LeechSeed", "Substitute", "Protect", "Endure", "Taunt",
      "Torment", "Encore", "Disable", "Yawn", "PerishSong", "AquaRing",
      "Ingrain", "Charge", "MagnetRise", "Telekinesis", "Toxic",
      "Attract", "FocusEnergy", "Embargo", "HealBlock", "GastroAcid",
      "Type3", "Truant", "Roost"
    ])
    return data
  rescue Exception
    return nil
  end

  def self.field_effects_data(battle)
    effects = safe(nil) { battle.field.effects }
    return effects_hash(effects, [
      "TrickRoom", "MagicRoom", "WonderRoom", "Gravity", "ElectricTerrain",
      "GrassyTerrain", "MistyTerrain", "PsychicTerrain", "MudSportField",
      "WaterSportField", "FairyLock"
    ])
  rescue Exception
    return {}
  end

  def self.battle_state(battle)
    active = []
    for battler in safe([]) { battle.battlers }
      data = active_battler_data(battle, battler)
      active.push(data) if data
    end
    weather = safe(0) { battle.pbWeather.to_i }
    return {
      "generatedAt" => Time.now.to_s,
      "source" => "Pokemon Z SebiLink Battle Advisor",
      "battle" => {
        "turn" => safe(0) { battle.turncount.to_i },
        "decision" => safe(0) { battle.decision.to_i },
        "doubleBattle" => safe(false) { battle.doublebattle ? true : false },
        "trainerBattle" => safe(false) { battle.opponent ? true : false },
        "pvpBattle" => safe(false) { battle.instance_variable_get("@sebi_pvp_session") ? true : false },
        "canEscape" => safe(true) { !battle.cantescape },
        "weather" => weather,
        "weatherName" => weather_name(weather),
        "weatherDuration" => safe(0) { battle.weatherduration.to_i },
        "environment" => safe(0) { battle.environment.to_i },
        "environmentName" => environment_name(safe(0) { battle.environment.to_i }),
        "fieldEffects" => field_effects_data(battle)
      },
      "player" => trainer_data(safe(nil) { battle.player }),
      "opponent" => trainer_data(safe(nil) { battle.opponent }),
      "activeBattlers" => active,
      "playerParty" => party_data(safe([]) { battle.party1 }, "playerParty"),
      "opponentParty" => party_data(safe([]) { battle.party2 }, "opponentParty"),
      "notes" => [
        "Los battlerIndex pares suelen ser del jugador y los impares del rival en este motor.",
        "La recomendacion debe priorizar el turno actual y puede sugerir cambio si es mas seguro."
      ]
    }
  rescue Exception
    return {
      "generatedAt" => Time.now.to_s,
      "error" => $!.message.to_s
    }
  end

  def self.owned_pokemon_refs
    refs = []
    if $Trainer && $Trainer.party
      for i in 0...$Trainer.party.length
        pokemon = $Trainer.party[i]
        refs.push({ "pokemon" => pokemon, "loc" => "party", "index" => i, "box" => nil, "slot" => nil }) if pokemon
      end
    end
    if defined?($PokemonStorage) && $PokemonStorage
      boxes = safe([]) { $PokemonStorage.boxes }
      for b in 0...boxes.length
        box = boxes[b]
        next if !box
        for s in 0...box.length
          pokemon = box[s]
          refs.push({ "pokemon" => pokemon, "loc" => "box", "index" => s, "box" => b, "slot" => s }) if pokemon
        end
      end
    end
    return refs
  rescue Exception
    return refs || []
  end

  def self.max_owned_level(refs)
    max_level = 1
    refs.each do |ref|
      pokemon = ref["pokemon"] rescue nil
      next if !pokemon
      next if safe(false) { pokemon.isEgg? ? true : false }
      level = safe(0) { pokemon.level.to_i }
      max_level = level if level > max_level
    end
    return max_level
  rescue Exception
    return 1
  end

  def self.team_party_data(analysis_level)
    ret = []
    return ret if !$Trainer || !$Trainer.party
    for i in 0...$Trainer.party.length
      data = team_pokemon_data($Trainer.party[i], "party", i, nil, nil, analysis_level)
      ret.push(data) if data
    end
    return ret
  rescue Exception
    return []
  end

  def self.team_storage_data(analysis_level)
    ret = { "currentBox" => 0, "boxes" => [] }
    return ret if !defined?($PokemonStorage) || !$PokemonStorage
    ret["currentBox"] = safe(0) { $PokemonStorage.currentBox.to_i }
    boxes = safe([]) { $PokemonStorage.boxes }
    for b in 0...boxes.length
      box = boxes[b]
      next if !box
      pokemon_list = []
      for s in 0...box.length
        data = team_pokemon_data(box[s], "box", s, b, s, analysis_level)
        pokemon_list.push(data) if data
      end
      ret["boxes"].push({
        "index" => b,
        "name" => safe("Caja " + (b + 1).to_s) { box.name.to_s },
        "length" => safe(30) { box.length.to_i },
        "count" => pokemon_list.length,
        "pokemon" => pokemon_list
      })
    end
    return ret
  rescue Exception
    return ret
  end

  def self.team_state
    refs = owned_pokemon_refs
    analysis_level = max_owned_level(refs)
    party = team_party_data(analysis_level)
    storage = team_storage_data(analysis_level)
    pc_count = 0
    safe([]) { storage["boxes"] }.each { |box| pc_count += safe(0) { box["count"].to_i } }
    return {
      "generatedAt" => Time.now.to_s,
      "source" => "Pokemon Z SebiLink Team Advisor",
      "game" => {
        "title" => "Pokemon Z",
        "creator" => "ericlostie",
        "engine" => "RPG Maker XP / Pokemon Essentials",
        "notes" => [
          "Usa los datos locales exportados desde Pokemon Z; puede haber especies, movimientos o balance custom.",
          "No inventes movimientos, objetos, habilidades ni especies que no aparezcan en este JSON."
        ]
      },
      "teamAnalysisLevel" => analysis_level,
      "levelRule" => "Para crear equipo, todos los Pokemon se consideran subibles al nivel del Pokemon mas alto del equipo o PC.",
      "trainer" => trainer_data($Trainer),
      "counts" => {
        "party" => party.length,
        "pc" => pc_count,
        "totalOwned" => party.length + pc_count
      },
      "party" => party,
      "storage" => storage,
      "notes" => [
        "learnableLevelMovesCurrent incluye movimientos por nivel hasta el nivel actual del Pokemon.",
        "learnableLevelMovesAtAnalysisLevel incluye movimientos por nivel hasta teamAnalysisLevel.",
        "newLevelMovesByAnalysisLevel incluye solo movimientos nuevos entre el nivel actual y teamAnalysisLevel.",
        "Si un movimiento no aparece en movimientos actuales ni en listas aprendibles por nivel, no lo recomiendes como aprendible."
      ]
    }
  rescue Exception
    return {
      "generatedAt" => Time.now.to_s,
      "error" => $!.message.to_s
    }
  end

  def self.write_state(battle)
    ensure_runtime
    atomic_write(state_path, json(battle_state(battle)))
    return true
  rescue Exception
    return false
  end

  def self.write_team_state
    ensure_runtime
    atomic_write(team_state_path, json(team_state))
    return true
  rescue Exception
    return false
  end

  def self.quote_arg(value)
    return "\"" + value.to_s.gsub("\"", "") + "\""
  rescue Exception
    return "\"\""
  end

  def self.open_powershell_script(path, extra_params = nil)
    if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:open_path)
      return SebiSaveEditor.open_path(path) if !extra_params || extra_params.to_s == ""
    end
    params = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " + quote_arg(path)
    params += " " + extra_params.to_s if extra_params && extra_params.to_s != ""
    if defined?(Win32API)
      shell = Win32API.new("shell32", "ShellExecuteA", "LPPPPI", "I")
      result = shell.call(0, "open", "powershell.exe", params, nil, 0)
      return true if result && result.to_i > 32
    end
    system("cmd /c start \"\" powershell.exe " + params)
    return true
  rescue Exception
    return false
  end

  def self.open(battle = nil)
    battle = SebiLinkHub.current_battle if !battle && defined?(SebiLinkHub)
    return false if !battle
    return false if !write_state(battle)
    path = window_path
    return false if !FileTest.exist?(path)
    return open_powershell_script(path)
  rescue Exception
    SebiVisualMultiplayer.log("No se pudo abrir consejo IA: " + $!.message.to_s) if defined?(SebiVisualMultiplayer)
    return false
  end
end

module SebiSavedTeams
  RELATIVE_PATH = "pvp-teams/showdown_teams.txt"
  TEAM_SIZE = 6

  def self.file_path
    return SebiLinkPaths.config_path(RELATIVE_PATH) if defined?(SebiLinkPaths)
    return File.expand_path("multiplayer/pvp-teams/showdown_teams.txt")
  rescue Exception
    return "multiplayer/pvp-teams/showdown_teams.txt"
  end

  def self.seed_path
    return File.join(SebiLinkPaths.multiplayer_dir, RELATIVE_PATH) if defined?(SebiLinkPaths)
    return File.expand_path("multiplayer/pvp-teams/showdown_teams.txt")
  rescue Exception
    return "multiplayer/pvp-teams/showdown_teams.txt"
  end

  def self.ensure_parent(path)
    SebiLinkPaths.ensure_dir(File.dirname(path)) if defined?(SebiLinkPaths)
  rescue Exception
  end

  def self.default_text
    return "=== Equipo de ejemplo ===\r\n" +
           "Tyranitar @ Leftovers\r\n" +
           "Ability: Sand Stream\r\n" +
           "Level: 50\r\n" +
           "EVs: 252 HP / 252 Atk / 4 SpD\r\n" +
           "Adamant Nature\r\n" +
           "- Stone Edge\r\n" +
           "- Crunch\r\n" +
           "- Earthquake\r\n" +
           "- Stealth Rock\r\n"
  end

  def self.read_file_text(path)
    return "" if !path || !FileTest.exist?(path)
    text = ""
    File.open(path, "rb") { |file| text = file.read.to_s }
    return text
  rescue Exception
    return ""
  end

  def self.write_file_text(path, text)
    ensure_parent(path)
    File.open(path, "wb") { |file| file.write(text.to_s) }
    return true
  rescue Exception
    return false
  end

  def self.ensure_file
    path = file_path
    return path if FileTest.exist?(path)
    text = read_file_text(seed_path)
    text = default_text if text.to_s.strip == ""
    write_file_text(path, text)
    return path
  rescue Exception
    return file_path
  end

  def self.raw_text
    return read_file_text(ensure_file)
  rescue Exception
    return ""
  end

  def self.clean_team_name(name)
    value = name.to_s.gsub(/\r|\n/, " ").strip
    value = _INTL("Equipo sin nombre") if value == ""
    return value
  rescue Exception
    return "Equipo"
  end

  def self.parse_teams(text = nil)
    text = raw_text if text == nil
    teams = []
    current_name = nil
    current_lines = []
    flush = proc do
      body = current_lines.join("").strip
      if body != ""
        teams.push({ "name" => clean_team_name(current_name || _INTL("Equipo {1}", teams.length + 1)), "text" => body })
      end
      current_lines = []
    end
    text.to_s.gsub(/\r\n?/, "\n").each_line do |line|
      stripped = line.strip
      if stripped =~ /^={3,}\s*(.*?)\s*={3,}$/
        flush.call
        current_name = $1.to_s.strip
      else
        current_lines.push(line)
      end
    end
    flush.call
    if teams.length == 0 && text.to_s.strip != ""
      teams.push({ "name" => _INTL("Equipo 1"), "text" => text.to_s.strip })
    end
    return teams
  rescue Exception
    return []
  end

  def self.teams
    return parse_teams(raw_text)
  rescue Exception
    return []
  end

  def self.write_teams(teams)
    text = ""
    for team in (teams || [])
      body = team["text"].to_s.gsub(/\r\n?/, "\n").strip
      next if body == ""
      text += "=== " + clean_team_name(team["name"]) + " ===\r\n"
      text += body.gsub("\n", "\r\n") + "\r\n\r\n"
    end
    return write_file_text(file_path, text)
  rescue Exception
    return false
  end

  def self.open_file_in_editor
    path = ensure_file
    if defined?(Win32API)
      shell = Win32API.new("shell32", "ShellExecuteA", "LPPPPI", "I")
      result = shell.call(0, "open", "notepad.exe", "\"" + path.to_s + "\"", nil, 1)
      return true if result && result.to_i > 32
    end
    system("cmd /c start \"\" notepad.exe \"" + path.to_s + "\"")
    return true
  rescue Exception
    return false
  end

  def self.prompt_text(message, default_value = "", max_length = 128)
    if defined?(SebiVisualMultiplayer) && SebiVisualMultiplayer.respond_to?(:prompt_text)
      return SebiVisualMultiplayer.prompt_text(message, default_value, max_length)
    end
    return Kernel.pbMessageFreeText(message, default_value.to_s, false, max_length)
  rescue Exception
    return nil
  end

  def self.choose_team(message = nil, default_name = nil)
    list = teams
    if list.length == 0
      Kernel.pbMessage(_INTL("No hay equipos guardados todavia. Se abrira el archivo para pegar equipos Showdown."))
      open_file_in_editor
      return nil
    end
    commands = []
    for team in list
      count = split_sets(team["text"]).length
      commands.push(_INTL("{1} ({2}/6)", team["name"].to_s, count))
    end
    commands.push(_INTL("Cancelar"))
    default_index = 0
    list.each_with_index { |team, index| default_index = index if team["name"].to_s == default_name.to_s }
    cmd = Kernel.pbMessage(message || _INTL("Elige equipo guardado"), commands, commands.length, nil, default_index)
    return nil if cmd < 0 || cmd >= list.length
    return list[cmd]
  rescue Exception
    return nil
  end

  def self.choose_team_name(message = nil)
    team = choose_team(message)
    return nil if !team
    return team["name"].to_s
  rescue Exception
    return nil
  end

  def self.team_by_name(name)
    value = name.to_s
    list = teams
    for team in list
      return team if team["name"].to_s == value
    end
    return list[0] if value == "" && list.length > 0
    return nil
  rescue Exception
    return nil
  end

  def self.showdown_key(value)
    return value.to_s.upcase.gsub(/[^A-Z0-9]/, "")
  rescue Exception
    return ""
  end

  def self.max_const_value(mod)
    return mod.maxValue.to_i if mod && mod.respond_to?(:maxValue)
    max = 0
    for name in mod.constants
      value = mod.const_get(name) rescue 0
      max = value.to_i if value.to_i > max
    end
    return max
  rescue Exception
    return 0
  end

  def self.id_from_name(mod_name, value)
    return 0 if value == nil || value.to_s.strip == ""
    @id_name_cache = {} if !@id_name_cache
    key = mod_name.to_s + ":" + showdown_key(value)
    return @id_name_cache[key] if @id_name_cache.has_key?(key)
    mod = Object.const_get(mod_name.to_s) rescue nil
    return 0 if !mod
    variants = []
    base = value.to_s.strip
    variants.push(base)
    variants.push(base.gsub(/[’`]/, "'"))
    variants.push(base.gsub("-", " "))
    variants.push(base.split("-")[0].to_s) if base.include?("-")
    for text in variants
      sym = showdown_key(text)
      next if sym == ""
      begin
        id = getID(mod, sym.to_sym) if defined?(getID)
        if id && id.to_i > 0
          @id_name_cache[key] = id.to_i
          return id.to_i
        end
      rescue Exception
      end
      begin
        id = mod.const_get(sym)
        if id && id.to_i > 0
          @id_name_cache[key] = id.to_i
          return id.to_i
        end
      rescue Exception
      end
    end
    target = showdown_key(base)
    max = max_const_value(mod)
    if max > 0 && mod.respond_to?(:getName)
      for id in 1..max
        name = mod.getName(id).to_s rescue ""
        if showdown_key(name) == target
          @id_name_cache[key] = id
          return id
        end
      end
    end
    @id_name_cache[key] = 0
    return 0
  rescue Exception
    return 0
  end

  def self.name_from_id(mod_name, id)
    mod = Object.const_get(mod_name.to_s) rescue nil
    return "" if !mod || id.to_i <= 0
    return mod.getName(id.to_i).to_s if mod.respond_to?(:getName)
    return id.to_i.to_s
  rescue Exception
    return id.to_i.to_s
  end

  def self.stat_index(stat)
    key = stat.to_s.upcase.gsub(/[^A-Z]/, "")
    return 0 if key == "HP" || key == "PS"
    return 1 if key == "ATK" || key == "ATA"
    return 2 if key == "DEF"
    return 3 if key == "SPE" || key == "VEL"
    return 4 if key == "SPA" || key == "SPATK" || key == "ATQESP" || key == "ATAESP"
    return 5 if key == "SPD" || key == "SPDDEF" || key == "SPDEF" || key == "SDEF" || key == "DEFESP"
    return nil
  rescue Exception
    return nil
  end

  def self.parse_spread(text, default_value)
    values = [default_value, default_value, default_value, default_value, default_value, default_value]
    text.to_s.split("/").each do |part|
      if part.strip =~ /(\d+)\s+(.+)/
        amount = $1.to_i
        index = stat_index($2)
        values[index] = amount if index != nil
      end
    end
    return values
  rescue Exception
    return [default_value, default_value, default_value, default_value, default_value, default_value]
  end

  def self.split_sets(text)
    sets = []
    current = []
    text.to_s.gsub(/\r\n?/, "\n").each_line do |line|
      if line.strip == ""
        if current.length > 0
          sets.push(current.join(""))
          current = []
        end
      else
        current.push(line)
      end
    end
    sets.push(current.join("")) if current.length > 0
    return sets
  rescue Exception
    return []
  end

  def self.parse_first_line(line)
    text = line.to_s.strip
    item = ""
    at = text.index("@")
    if at
      item = text[(at + 1)..-1].to_s.strip
      text = text[0...at].to_s.strip
    end
    gender = nil
    if text =~ /\((M|F)\)\s*$/i
      gender = $1.to_s.upcase
      text = text.sub(/\((M|F)\)\s*$/i, "").strip
    end
    nickname = ""
    species = text
    if text =~ /^(.*?)\s*\(([^()]*)\)\s*$/
      nickname = $1.to_s.strip
      species = $2.to_s.strip
    end
    return [species, nickname, gender, item]
  rescue Exception
    return [line.to_s, "", nil, ""]
  end

  def self.set_item(pokemon, item_id)
    return if !pokemon
    pokemon.item = item_id.to_i if pokemon.respond_to?(:item=)
    pokemon.itemInitial = item_id.to_i if pokemon.respond_to?(:itemInitial=)
  rescue Exception
  end

  def self.set_ability_by_name(pokemon, ability_name)
    id = id_from_name("PBAbilities", ability_name)
    return false if !pokemon || id.to_i <= 0
    for flag in 0..2
      begin
        pokemon.abilityflag = flag if pokemon.respond_to?(:abilityflag=)
        if (pokemon.ability.to_i rescue 0) == id.to_i
          return true
        end
      rescue Exception
      end
    end
    return false
  rescue Exception
    return false
  end

  def self.assign_moves(pokemon, move_ids)
    return false if !pokemon || !defined?(PBMove)
    ids = []
    for id in (move_ids || [])
      ids.push(id.to_i) if id.to_i > 0 && !ids.include?(id.to_i)
      break if ids.length >= 4
    end
    return false if ids.length == 0
    for i in 0...4
      pokemon.moves[i] = PBMove.new(ids[i].to_i) if ids[i]
      pokemon.moves[i] = PBMove.new(0) if !ids[i]
    end
    pokemon.firstmoves = ids if pokemon.respond_to?(:firstmoves=)
    return true
  rescue Exception
    return false
  end

  def self.no_damage_move_id
    [:SPLASH, :PROTECT, :DETECT, :GROWL, :LEER, :TAILWHIP, :HARDEN].each do |symbol|
      id = id_from_name("PBMoves", symbol.to_s)
      return id if id.to_i > 0
    end
    return 0
  rescue Exception
    return 0
  end

  def self.force_no_damage_moves(party)
    id = no_damage_move_id
    return party if id.to_i <= 0
    for pokemon in (party || [])
      assign_moves(pokemon, [id, id, id, id]) if pokemon
    end
    return party
  rescue Exception
    return party
  end

  def self.pokemon_from_showdown(block)
    lines = []
    block.to_s.gsub(/\r\n?/, "\n").each_line do |line|
      stripped = line.strip
      next if stripped == "" || stripped[0, 1] == "#"
      lines.push(stripped)
    end
    return nil if lines.length == 0
    species_text, nickname, gender, item_text = parse_first_line(lines[0])
    species = id_from_name("PBSpecies", species_text)
    return nil if species.to_i <= 0
    level = 50
    ability_name = ""
    nature_name = ""
    evs = [0, 0, 0, 0, 0, 0]
    ivs = [31, 31, 31, 31, 31, 31]
    shiny = false
    moves = []
    for i in 1...lines.length
      line = lines[i]
      if line =~ /^Ability:\s*(.+)$/i
        ability_name = $1.to_s.strip
      elsif line =~ /^Level:\s*(\d+)/i
        level = $1.to_i
      elsif line =~ /^Shiny:\s*Yes/i
        shiny = true
      elsif line =~ /^EVs:\s*(.+)$/i
        evs = parse_spread($1, 0)
      elsif line =~ /^IVs:\s*(.+)$/i
        ivs = parse_spread($1, 31)
      elsif line =~ /^(.+)\s+Nature$/i
        nature_name = $1.to_s.strip
      elsif line =~ /^-\s*(.+)$/i
        move_text = $1.to_s.strip
        move_text = move_text.sub(/\s*\[.*\]\s*$/, "").strip
        move_id = id_from_name("PBMoves", move_text)
        moves.push(move_id) if move_id.to_i > 0
      end
    end
    level = 1 if level < 1
    pokemon = PokeBattle_Pokemon.new(species.to_i, level, $Trainer)
    pokemon.name = nickname if nickname && nickname != ""
    set_item(pokemon, id_from_name("PBItems", item_text)) if item_text && item_text != ""
    pokemon.iv = ivs if pokemon.respond_to?(:iv=)
    pokemon.ev = evs if pokemon.respond_to?(:ev=)
    nature = id_from_name("PBNatures", nature_name)
    pokemon.natureflag = nature.to_i if nature.to_i > 0 && pokemon.respond_to?(:natureflag=)
    if gender
      pokemon.genderflag = (gender == "F" ? 1 : 0) if pokemon.respond_to?(:genderflag=)
    end
    if shiny
      pokemon.makeShiny if pokemon.respond_to?(:makeShiny)
      pokemon.shinyflag = true if pokemon.respond_to?(:shinyflag=)
    end
    set_ability_by_name(pokemon, ability_name) if ability_name != ""
    if moves.length > 0
      assign_moves(pokemon, moves)
    else
      pokemon.resetMoves if pokemon.respond_to?(:resetMoves)
    end
    pokemon.calcStats if pokemon.respond_to?(:calcStats)
    pokemon.heal if pokemon.respond_to?(:heal)
    return pokemon
  rescue Exception
    return nil
  end

  def self.party_from_team(team, no_damage = false)
    return [nil, _INTL("No se ha elegido ningun equipo guardado.")] if !team
    party = []
    for block in split_sets(team["text"])
      pokemon = pokemon_from_showdown(block)
      party.push(pokemon) if pokemon
      break if party.length >= TEAM_SIZE
    end
    if party.length < TEAM_SIZE
      return [nil, _INTL("El equipo guardado '{1}' no se pudo crear completo ({2}/6). Revisa especies, objetos o movimientos del archivo Showdown.", team["name"].to_s, party.length)]
    end
    force_no_damage_moves(party) if no_damage
    return [party, nil]
  rescue Exception
    return [nil, _INTL("No se pudo cargar el equipo guardado.")]
  end

  def self.showdown_spread(label, values, default_value)
    order = [[0, "HP"], [1, "Atk"], [2, "Def"], [4, "SpA"], [5, "SpD"], [3, "Spe"]]
    parts = []
    for entry in order
      value = values[entry[0]].to_i rescue default_value
      next if value.to_i == default_value.to_i
      parts.push(value.to_i.to_s + " " + entry[1])
    end
    return "" if parts.length == 0
    return label + ": " + parts.join(" / ")
  rescue Exception
    return ""
  end

  def self.pokemon_to_showdown(pokemon)
    return "" if !pokemon
    species = name_from_id("PBSpecies", pokemon.species.to_i)
    name = pokemon.name.to_s rescue species
    item = name_from_id("PBItems", pokemon.item.to_i)
    header = species
    header = name + " (" + species + ")" if name != "" && name != species
    header += " @ " + item if item != ""
    lines = [header]
    ability = name_from_id("PBAbilities", (pokemon.ability.to_i rescue 0))
    lines.push("Ability: " + ability) if ability != ""
    lines.push("Level: " + (pokemon.level.to_i rescue 50).to_s)
    lines.push("Shiny: Yes") if (pokemon.isShiny? rescue false)
    ev_line = showdown_spread("EVs", (pokemon.ev rescue []), 0)
    iv_line = showdown_spread("IVs", (pokemon.iv rescue []), 31)
    lines.push(ev_line) if ev_line != ""
    nature = name_from_id("PBNatures", (pokemon.nature.to_i rescue 0))
    lines.push(nature + " Nature") if nature != ""
    lines.push(iv_line) if iv_line != ""
    moves = pokemon.moves rescue []
    for move in moves
      id = move.id.to_i rescue 0
      next if id <= 0
      move_name = name_from_id("PBMoves", id)
      lines.push("- " + move_name) if move_name != ""
    end
    return lines.join("\r\n")
  rescue Exception
    return ""
  end

  def self.party_to_showdown(party)
    blocks = []
    for pokemon in (party || [])
      text = pokemon_to_showdown(pokemon)
      blocks.push(text) if text != ""
    end
    return blocks.join("\r\n\r\n")
  rescue Exception
    return ""
  end

  def self.save_party(party, default_name = nil)
    if !party || party.length == 0
      Kernel.pbMessage(_INTL("No hay equipo para guardar."))
      return false
    end
    default_name = _INTL("Equipo guardado") if !default_name || default_name.to_s == ""
    name = prompt_text(_INTL("Nombre del equipo guardado."), default_name.to_s, 64)
    return false if !name || name.to_s.strip == ""
    body = party_to_showdown(party)
    if body == ""
      Kernel.pbMessage(_INTL("No se pudo convertir ese equipo a formato Showdown."))
      return false
    end
    list = teams
    list.push({ "name" => clean_team_name(name), "text" => body })
    if write_teams(list)
      Kernel.pbMessage(_INTL("Equipo '{1}' guardado en:\n{2}", clean_team_name(name), file_path))
      return true
    end
    Kernel.pbMessage(_INTL("No se pudo guardar el equipo."))
    return false
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo guardar el equipo: {1}", $!.message.to_s))
    return false
  end

  def self.save_current_party
    if !$Trainer || !$Trainer.party || $Trainer.party.length == 0
      Kernel.pbMessage(_INTL("No tienes equipo cargado."))
      return false
    end
    return save_party($Trainer.party, _INTL("Mi equipo"))
  rescue Exception
    return false
  end

  def self.rename_team
    list = teams
    team = choose_team(_INTL("Que equipo quieres renombrar?"))
    return if !team
    index = list.index(team)
    return if index == nil
    name = prompt_text(_INTL("Nuevo nombre del equipo."), team["name"].to_s, 64)
    return if !name || name.to_s.strip == ""
    list[index]["name"] = clean_team_name(name)
    write_teams(list)
    Kernel.pbMessage(_INTL("Equipo renombrado."))
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo renombrar el equipo."))
  end

  def self.delete_team
    list = teams
    team = choose_team(_INTL("Que equipo quieres borrar?"))
    return if !team
    return if !Kernel.pbConfirmMessage(_INTL("Borrar '{1}' del archivo de equipos?", team["name"].to_s))
    list.delete(team)
    write_teams(list)
    Kernel.pbMessage(_INTL("Equipo borrado."))
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo borrar el equipo."))
  end

  def self.create_blank_team
    name = prompt_text(_INTL("Nombre del nuevo equipo."), _INTL("Nuevo equipo"), 64)
    return if !name || name.to_s.strip == ""
    sample = "Pikachu @ Light Ball\r\nAbility: Static\r\nLevel: 50\r\nEVs: 252 Atk / 4 SpD / 252 Spe\r\nJolly Nature\r\n- Volt Tackle\r\n- Iron Tail\r\n- Quick Attack\r\n- Thunder Wave"
    list = teams
    list.push({ "name" => clean_team_name(name), "text" => sample })
    write_teams(list)
    Kernel.pbMessage(_INTL("Equipo creado con plantilla. Abre el archivo para pegar encima tu equipo Showdown."))
    open_file_in_editor
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo crear el equipo."))
  end

  def self.show_team_summary
    team = choose_team(_INTL("Que equipo quieres revisar?"))
    return if !team
    party, error = party_from_team(team, false)
    if error
      Kernel.pbMessage(error)
      return
    end
    if defined?(SebiPvpPreview)
      SebiPvpPreview.show_readonly_team(team["name"].to_s, party)
    else
      Kernel.pbMessage(_INTL("Equipo '{1}' cargado correctamente.", team["name"].to_s))
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo revisar el equipo."))
  end

  def self.open_manager
    ensure_file
    loop do
      commands = [
        _INTL("Ver/probar equipo"),
        _INTL("Guardar mi equipo actual"),
        _INTL("Crear equipo"),
        _INTL("Renombrar equipo"),
        _INTL("Borrar equipo"),
        _INTL("Abrir archivo Showdown"),
        _INTL("Salir")
      ]
      cmd = Kernel.pbMessage(_INTL("Equipos guardados\nFormato Showdown en:\n{1}", file_path), commands, commands.length)
      case cmd
      when 0
        show_team_summary
      when 1
        save_current_party
      when 2
        create_blank_team
      when 3
        rename_team
      when 4
        delete_team
      when 5
        open_file_in_editor
      else
        break
      end
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir equipos guardados: {1}", $!.message.to_s))
  end
end

module SebiPvpRules
  TEAM_SIZE = 6
  PVP_WAIT_DEFAULT_FRAMES = 108000
  PVP_LEGENDARY_SYMBOLS = %w[
    ARTICUNO ZAPDOS MOLTRES MEWTWO RAIKOU ENTEI SUICUNE LUGIA HOOH
    REGIROCK REGICE REGISTEEL LATIAS LATIOS KYOGRE GROUDON RAYQUAZA
    UXIE MESPRIT AZELF DIALGA PALKIA HEATRAN REGIGIGAS GIRATINA CRESSELIA
    COBALION TERRAKION VIRIZION TORNADUS THUNDURUS RESHIRAM ZEKROM LANDORUS KYUREM
    XERNEAS YVELTAL ZYGARDE TAPUKOKO TAPULELE TAPUBULU TAPUFINI COSMOG COSMOEM
    SOLGALEO LUNALA NECROZMA ZACIAN ZAMAZENTA ETERNATUS KUBFU URSHIFU REGIELEKI
    REGIDRAGO GLASTRIER SPECTRIER CALYREX ENAMORUS KORAIDON MIRAIDON OGERPON TERAPAGOS
    TYPENULL SILVALLY WOCHIEN CHIENPAO TINGLU CHIYU OKIDOGI MUNKIDORI FEZANDIPITI
  ]
  PVP_SPECIAL_NON_LEGENDARY_SYMBOLS = %w[
    UNOWN MEW CELEBI JIRACHI DEOXYS PHIONE MANAPHY DARKRAI SHAYMIN ARCEUS VICTINI
    KELDEO MELOETTA GENESECT DIANCIE HOOPA VOLCANION MAGEARNA MARSHADOW ZERAORA
    MELTAN MELMETAL ZARUDE PECHARUNT NIHILEGO BUZZWOLE PHEROMOSA XURKITREE
    CELESTEELA KARTANA GUZZLORD POIPOLE NAGANADEL STAKATAKA BLACEPHALON
  ]
  PVP_USAGE_SET_FILES = [
    "btpokemon.txt",
    "pokecuppm.txt",
    "fancycuppm.txt",
    "fancycupsinglepm.txt",
    "pikacuppm.txt"
  ]
  PVP_SET_STAT_INDEXES = {
    "HP" => 0,
    "ATK" => 1,
    "DEF" => 2,
    "SPD" => 3,
    "SPE" => 3,
    "SA" => 4,
    "SPA" => 4,
    "SPATK" => 4,
    "SD" => 5,
    "SPDDEF" => 5,
    "SPDEF" => 5
  }
  PVP_TYPE_ITEM_SYMBOLS = {
    "NORMAL" => "SILKSCARF",
    "FIRE" => "CHARCOAL",
    "WATER" => "MYSTICWATER",
    "ELECTRIC" => "MAGNET",
    "GRASS" => "MIRACLESEED",
    "ICE" => "NEVERMELTICE",
    "FIGHTING" => "BLACKBELT",
    "POISON" => "POISONBARB",
    "GROUND" => "SOFTSAND",
    "FLYING" => "SHARPBEAK",
    "PSYCHIC" => "TWISTEDSPOON",
    "BUG" => "SILVERPOWDER",
    "ROCK" => "HARDSTONE",
    "GHOST" => "SPELLTAG",
    "DRAGON" => "DRAGONFANG",
    "DARK" => "BLACKGLASSES",
    "STEEL" => "METALCOAT",
    "FAIRY" => "PIXIEPLATE"
  }
  PVP_TYPE_ITEM_EXTRA_SYMBOLS = {
    "SEAINCENSE" => "WATER",
    "WAVEINCENSE" => "WATER",
    "ODDINCENSE" => "PSYCHIC",
    "ROSEINCENSE" => "GRASS",
    "ROCKINCENSE" => "ROCK"
  }
  PVP_REASONABLE_USAGE_ITEM_SYMBOLS = %w[
    LEFTOVERS BLACKSLUDGE LIFEORB EXPERTBELT FOCUSSASH FOCUSBAND SHELLBELL QUICKCLAW
    WHITEHERB POWERHERB MENTALHERB LUMBERRY SITRUSBERRY WIDELENS SCOPELENS BRIGHTPOWDER
    LIGHTCLAY ROCKYHELMET AIRBALLOON WEAKNESSPOLICY EVIOLITE ASSAULTVEST
    CHOICEBAND CHOICESPECS CHOICESCARF MUSCLEBAND WISEGLASSES
    SALACBERRY LIECHIBERRY PETAYABERRY APICOTBERRY LANSATBERRY STARFBERRY
    CHESTOBERRY FIGYBERRY WIKIBERRY MAGOBERRY AGUAVBERRY IAPAPABERRY
    FLAMEORB TOXICORB KINGSROCK
  ]

  def self.default_rules
    return {
      "source" => "current",
      "level" => "current",
      "type" => "-1",
      "legends" => "0",
      "ivs" => "default",
      "iv_custom" => "31",
      "evs" => "default",
      "ev_custom" => "85",
      "items" => "default",
      "moves" => "default",
      "mega" => "default",
      "saved_team" => ""
    }
  end

  def self.clamp_int(value, min_value, max_value, default_value)
    number = value.to_i
    number = default_value.to_i if value == nil || value.to_s == ""
    number = min_value.to_i if number < min_value.to_i
    number = max_value.to_i if number > max_value.to_i
    return number
  rescue Exception
    return default_value.to_i
  end

  def self.normalize_rules(value)
    ret = default_rules
    if value
      for key in ret.keys
        ret[key] = value[key].to_s if value[key] != nil
      end
    end
    ret["source"] = "current" if !["current", "owned", "random", "teams", "ai", "saved"].include?(ret["source"])
    ret["level"] = "current" if !["current", "50", "100", "highest"].include?(ret["level"])
    ret["ivs"] = "default" if !["default", "random", "balanced", "zero", "recommended", "custom"].include?(ret["ivs"])
    ret["evs"] = "default" if !["default", "random", "balanced", "zero", "recommended", "custom"].include?(ret["evs"])
    ret["items"] = "default" if !["default", "random", "none", "recommended"].include?(ret["items"])
    ret["moves"] = "default" if !["default", "recommended", "random_learnable", "random_any"].include?(ret["moves"])
    ret["mega"] = "default" if !["default", "random"].include?(ret["mega"])
    ret["iv_custom"] = clamp_int(ret["iv_custom"], 0, 31, 31).to_s
    ret["ev_custom"] = clamp_int(ret["ev_custom"], 0, ev_stat_limit, 85).to_s
    ret["type"] = ret["type"].to_i.to_s
    ret["legends"] = "6" if ret["legends"].to_s == "all"
    legend_count = ret["legends"].to_i
    legend_count = 0 if legend_count < 0
    legend_count = TEAM_SIZE if legend_count > TEAM_SIZE
    ret["legends"] = legend_count.to_s
    return ret
  rescue Exception
    return default_rules
  end

  def self.current_rules
    value = default_rules
    if defined?(SebiLinkFileConfig)
      value["source"] = SebiLinkFileConfig.get("pvp_team_source", value["source"]).to_s
      value["level"] = SebiLinkFileConfig.get("pvp_level_rule", value["level"]).to_s
      value["type"] = SebiLinkFileConfig.get("pvp_monotype", value["type"]).to_s
      value["legends"] = SebiLinkFileConfig.get("pvp_legend_count", value["legends"]).to_s
      value["ivs"] = SebiLinkFileConfig.get("pvp_iv_rule", value["ivs"]).to_s
      value["iv_custom"] = SebiLinkFileConfig.get("pvp_iv_custom", value["iv_custom"]).to_s
      value["evs"] = SebiLinkFileConfig.get("pvp_ev_rule", value["evs"]).to_s
      value["ev_custom"] = SebiLinkFileConfig.get("pvp_ev_custom", value["ev_custom"]).to_s
      value["items"] = SebiLinkFileConfig.get("pvp_item_rule", value["items"]).to_s
      value["moves"] = SebiLinkFileConfig.get("pvp_move_rule", value["moves"]).to_s
      value["mega"] = SebiLinkFileConfig.get("pvp_mega_rule", value["mega"]).to_s
      value["saved_team"] = SebiLinkFileConfig.get("pvp_saved_team", value["saved_team"]).to_s
    end
    return normalize_rules(value)
  rescue Exception
    return default_rules
  end

  def self.save_rules(rules)
    rules = normalize_rules(rules)
    return if !defined?(SebiLinkFileConfig)
    SebiLinkFileConfig.set("pvp_team_source", rules["source"])
    SebiLinkFileConfig.set("pvp_level_rule", rules["level"])
    SebiLinkFileConfig.set("pvp_monotype", rules["type"])
    SebiLinkFileConfig.set("pvp_legend_count", rules["legends"])
    SebiLinkFileConfig.set("pvp_iv_rule", rules["ivs"])
    SebiLinkFileConfig.set("pvp_iv_custom", rules["iv_custom"])
    SebiLinkFileConfig.set("pvp_ev_rule", rules["evs"])
    SebiLinkFileConfig.set("pvp_ev_custom", rules["ev_custom"])
    SebiLinkFileConfig.set("pvp_item_rule", rules["items"])
    SebiLinkFileConfig.set("pvp_move_rule", rules["moves"])
    SebiLinkFileConfig.set("pvp_mega_rule", rules["mega"])
    SebiLinkFileConfig.set("pvp_saved_team", rules["saved_team"])
  rescue Exception
  end

  def self.encode(rules)
    rules = normalize_rules(rules)
    return [
      rules["source"],
      rules["level"],
      rules["type"],
      rules["legends"],
      rules["ivs"],
      rules["iv_custom"],
      rules["evs"],
      rules["ev_custom"],
      rules["items"],
      rules["moves"],
      rules["mega"],
      encode_rule_value(rules["saved_team"])
    ].join(",")
  end

  def self.encode_rule_value(value)
    text = value.to_s
    text = text.gsub("%", "%25")
    text = text.gsub(",", "%2C")
    return text
  rescue Exception
    return ""
  end

  def self.decode_rule_value(value)
    text = value.to_s
    text = text.gsub("%2C", ",")
    text = text.gsub("%25", "%")
    return text
  rescue Exception
    return ""
  end

  def self.decode(text)
    parts = text.to_s.split(",")
    if parts.length <= 7
      return normalize_rules({
        "source" => parts[0],
        "level" => parts[1],
        "type" => parts[2],
        "legends" => parts[3],
        "ivs" => parts[4],
        "evs" => parts[5],
        "items" => parts[6]
      })
    end
    if parts.length <= 9
      return normalize_rules({
        "source" => parts[0],
        "level" => parts[1],
        "type" => parts[2],
        "legends" => parts[3],
        "ivs" => parts[4],
        "iv_custom" => parts[5],
        "evs" => parts[6],
        "ev_custom" => parts[7],
        "items" => parts[8] || parts[6]
      })
    end
    if parts.length <= 10
      return normalize_rules({
        "source" => parts[0],
        "level" => parts[1],
        "type" => parts[2],
        "legends" => parts[3],
        "ivs" => parts[4],
        "iv_custom" => parts[5],
        "evs" => parts[6],
        "ev_custom" => parts[7],
        "items" => parts[8],
        "moves" => parts[9]
      })
    end
    return normalize_rules({
      "source" => parts[0],
      "level" => parts[1],
      "type" => parts[2],
      "legends" => parts[3],
      "ivs" => parts[4],
      "iv_custom" => parts[5],
      "evs" => parts[6],
      "ev_custom" => parts[7],
      "items" => parts[8],
      "moves" => parts[9],
      "mega" => parts[10],
      "saved_team" => decode_rule_value(parts[11])
    })
  rescue Exception
    return default_rules
  end

  def self.source_label(source)
    return _INTL("Equipo actual") if source.to_s == "current"
    return _INTL("Aleatorios de mis Pokemon") if source.to_s == "owned"
    return _INTL("Aleatorios totales") if source.to_s == "random"
    return _INTL("Equipos random") if source.to_s == "teams"
    return _INTL("Equipo elegido por IA") if source.to_s == "ai"
    return _INTL("Equipo guardado Showdown") if source.to_s == "saved"
    return source.to_s
  end

  def self.level_label(level)
    return _INTL("Sin igualar") if level.to_s == "current"
    return _INTL("Nivel 50") if level.to_s == "50"
    return _INTL("Nivel 100") if level.to_s == "100"
    return _INTL("Al pokemon lvl mas alto") if level.to_s == "highest"
    return level.to_s
  end

  def self.type_name(type)
    return _INTL("Aleatorio") if type.to_i == -2
    return _INTL("Cualquier tipo") if type.to_i < 0
    return PBTypes.getName(type.to_i).to_s if defined?(PBTypes)
    return type.to_s
  rescue Exception
    return type.to_s
  end

  def self.legend_label(value)
    count = value.to_i
    return _INTL("Sin legendarios") if count <= 0
    return _INTL("1 legendario") if count == 1
    return _INTL("{1} legendarios", count)
  end

  def self.iv_label(value, custom_value = nil)
    return _INTL("Por defecto") if value.to_s == "default"
    return _INTL("Aleatorios (0-31)") if value.to_s == "random"
    return _INTL("Equilibrados (16 cada stat)") if value.to_s == "balanced"
    return _INTL("Sin IVs") if value.to_s == "zero"
    return _INTL("Recomendados") if value.to_s == "recommended"
    return _INTL("Personalizados ({1} cada stat)", clamp_int(custom_value, 0, 31, 31)) if value.to_s == "custom"
    return value.to_s
  end

  def self.ev_label(value, custom_value = nil)
    return _INTL("Por defecto") if value.to_s == "default"
    return _INTL("Aleatorios (510 repartidos)") if value.to_s == "random"
    return _INTL("Equilibrados (85 cada stat)") if value.to_s == "balanced"
    return _INTL("Sin EVs") if value.to_s == "zero"
    return _INTL("Recomendados") if value.to_s == "recommended"
    return _INTL("Personalizados ({1} cada stat)", clamp_int(custom_value, 0, ev_stat_limit, 85)) if value.to_s == "custom"
    return value.to_s
  end

  def self.item_label(value)
    return _INTL("Por defecto") if value.to_s == "default"
    return _INTL("Aleatorios") if value.to_s == "random"
    return _INTL("Sin objeto") if value.to_s == "none"
    return _INTL("Recomendados") if value.to_s == "recommended"
    return value.to_s
  end

  def self.move_rule_label(value)
    return _INTL("Por defecto") if value.to_s == "default"
    return _INTL("Recomendados") if value.to_s == "recommended"
    return _INTL("Aleatorios aprendibles") if value.to_s == "random_learnable"
    return _INTL("Aleatorios completos") if value.to_s == "random_any"
    return value.to_s
  end

  def self.mega_label(value)
    return _INTL("Por defecto") if value.to_s == "default"
    return _INTL("Mega aleatoria") if value.to_s == "random"
    return value.to_s
  end

  def self.summary(rules = nil)
    rules = normalize_rules(rules || current_rules)
    text = source_label(rules["source"]) + ", " + level_label(rules["level"])
    if rules["source"] != "current"
      text += ", " + type_name(rules["type"].to_i) + ", " + legend_label(rules["legends"])
    end
    text += ", IVs " + iv_label(rules["ivs"], rules["iv_custom"])
    text += ", EVs " + ev_label(rules["evs"], rules["ev_custom"])
    text += ", objetos " + item_label(rules["items"])
    text += ", movimientos " + move_rule_label(rules["moves"])
    text += ", mega " + mega_label(rules["mega"])
    text += ", " + rules["saved_team"].to_s if rules["source"] == "saved" && rules["saved_team"].to_s != ""
    return text
  rescue Exception
    return _INTL("Reglas PvP")
  end

  def self.choose_from(message, labels, values, current)
    commands = []
    for i in 0...labels.length
      prefix = values[i].to_s == current.to_s ? "> " : ""
      commands.push(prefix + labels[i].to_s)
    end
    commands.push(_INTL("Cancelar"))
    cmd = Kernel.pbMessage(message, commands, commands.length)
    return nil if cmd < 0 || cmd >= values.length
    return values[cmd]
  rescue Exception
    return nil
  end

  def self.type_options
    ids = [-1, -2]
    labels = [_INTL("Cualquier tipo"), _INTL("Aleatorio")]
    return [labels, ids] if !defined?(PBTypes)
    max = PBTypes.maxValue rescue 0
    for id in 0..max
      name = PBTypes.getName(id).to_s rescue ""
      next if name == "" || name == "???" || name.downcase == "shadow"
      ids.push(id)
      labels.push(name)
    end
    return [labels, ids]
  rescue Exception
    return [labels || [_INTL("Cualquier tipo"), _INTL("Aleatorio")], ids || [-1, -2]]
  end

  def self.random_type_id
    labels, ids = type_options
    valid = []
    for id in ids
      valid.push(id.to_i) if id.to_i >= 0
    end
    return -1 if valid.length == 0
    return valid[rand(valid.length)]
  rescue Exception
    return -1
  end

  def self.rules_for_request(rules)
    ret = normalize_rules(rules)
    if ret["type"].to_i == -2
      chosen = random_type_id
      ret["type"] = chosen.to_s if chosen >= 0
    end
    return ret
  rescue Exception
    return normalize_rules(rules)
  end

  def self.choose_legend_count(current)
    commands = [
      _INTL("Sin legendarios"),
      _INTL("Elegir cantidad entre 1 y 6"),
      _INTL("Cancelar")
    ]
    cmd = Kernel.pbMessage(_INTL("Cantidad exacta de legendarios para equipos aleatorios o de IA."), commands, commands.length)
    return "0" if cmd == 0
    return nil if cmd != 1
    params = ChooseNumberParams.new
    params.setRange(1, TEAM_SIZE)
    value = current.to_i
    value = 1 if value < 1
    value = TEAM_SIZE if value > TEAM_SIZE
    params.setDefaultValue(value)
    params.setCancelValue(-1)
    chosen = Kernel.pbMessageChooseNumber(_INTL("Cuantos Pokemon legendarios debe tener el equipo?"), params).to_i
    return nil if chosen < 1
    return chosen.to_s
  rescue Exception
    return nil
  end

  def self.choose_custom_stat_value(message, current, min_value, max_value, default_value)
    params = ChooseNumberParams.new
    params.setRange(min_value.to_i, max_value.to_i)
    params.setDefaultValue(clamp_int(current, min_value, max_value, default_value))
    params.setCancelValue(-1)
    value = Kernel.pbMessageChooseNumber(message, params).to_i
    return nil if value < min_value.to_i
    return clamp_int(value, min_value, max_value, default_value).to_s
  rescue Exception
    return nil
  end

  def self.open_menu
    if defined?(SebiVisualMultiplayer)
      SebiVisualMultiplayer.open_battle_menu
    else
      Kernel.pbMessage(_INTL("No se pudo abrir la seleccion de jugador."))
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir el combate PvP."))
  end

  def self.open_challenge_menu(player)
    return if !player
    rules = current_rules
    mode = SebiLinkFileConfig.get("pvp_format", "single")
    mode = "single" if !["single", "double"].include?(mode)
    loop do
      commands = [
        _INTL("Formato: {1}", mode == "double" ? _INTL("2vs2") : _INTL("1vs1")),
        _INTL("Origen del equipo: {1}", source_label(rules["source"])),
        _INTL("Niveles: {1}", level_label(rules["level"])),
        _INTL("Monotipo: {1}", type_name(rules["type"].to_i)),
        _INTL("Legendarios: {1}", legend_label(rules["legends"])),
        _INTL("IVs: {1}", iv_label(rules["ivs"], rules["iv_custom"])),
        _INTL("EVs: {1}", ev_label(rules["evs"], rules["ev_custom"])),
        _INTL("Objetos: {1}", item_label(rules["items"])),
        _INTL("Movimientos: {1}", move_rule_label(rules["moves"])),
        _INTL("Mega: {1}", mega_label(rules["mega"])),
        _INTL("Enviar solicitud de combate"),
        _INTL("Cancelar")
      ]
      cmd = Kernel.pbMessage(
        _INTL("Combatir contra {1}\nPersonaliza el combate a tu gusto.", player.remote_name),
        commands,
        commands.length
      )
      case cmd
      when 0
        value = choose_from(
          _INTL("Formato del combate."),
          [_INTL("1vs1"), _INTL("2vs2")],
          ["single", "double"],
          mode
        )
        if value
          mode = value
          SebiLinkFileConfig.set("pvp_format", mode)
        end
      when 1
        value = choose_from(
          _INTL("Origen del equipo temporal."),
          [_INTL("Equipo actual"), _INTL("Aleatorios de mis Pokemon"), _INTL("Aleatorios totales"), _INTL("Equipos random"), _INTL("Equipo guardado Showdown"), _INTL("Equipo elegido por IA")],
          ["current", "owned", "random", "teams", "saved", "ai"],
          rules["source"]
        )
        if value
          if value == "saved" && defined?(SebiSavedTeams)
            team_name = SebiSavedTeams.choose_team_name(_INTL("Elige el equipo Showdown que usaras tu."))
            if team_name
              rules["saved_team"] = team_name
              rules["source"] = value
            end
          else
            rules["source"] = value
          end
        end
      when 2
        value = choose_from(
          _INTL("Regla de nivel del combate."),
          [_INTL("Sin igualar"), _INTL("Nivel 50"), _INTL("Nivel 100"), _INTL("Al pokemon lvl mas alto")],
          ["current", "50", "100", "highest"],
          rules["level"]
        )
        rules["level"] = value if value
      when 3
        labels, values = type_options
        value = choose_from(_INTL("Tipo obligatorio para equipos aleatorios o de IA."), labels, values, rules["type"].to_i)
        rules["type"] = value.to_i.to_s if value != nil
      when 4
        value = choose_legend_count(rules["legends"])
        rules["legends"] = value if value
      when 5
        value = choose_from(
          _INTL("Regla temporal de IVs para los Pokemon del combate."),
          [_INTL("Por defecto"), _INTL("Aleatorios (0-31)"), _INTL("Equilibrados (16 cada stat)"), _INTL("Sin IVs"), _INTL("Recomendados"), _INTL("Personalizado")],
          ["default", "random", "balanced", "zero", "recommended", "custom"],
          rules["ivs"]
        )
        if value == "custom"
          custom = choose_custom_stat_value(_INTL("IV personalizado para las 6 stats (0-31)."), rules["iv_custom"], 0, 31, 31)
          if custom
            rules["iv_custom"] = custom
            rules["ivs"] = value
          end
        else
          rules["ivs"] = value if value
        end
      when 6
        value = choose_from(
          _INTL("Regla temporal de EVs para los Pokemon del combate."),
          [_INTL("Por defecto"), _INTL("Aleatorios (510 repartidos)"), _INTL("Equilibrados (85 cada stat)"), _INTL("Sin EVs"), _INTL("Recomendados"), _INTL("Personalizado")],
          ["default", "random", "balanced", "zero", "recommended", "custom"],
          rules["evs"]
        )
        if value == "custom"
          custom = choose_custom_stat_value(_INTL("EV personalizado para las 6 stats (0-{1}).", ev_stat_limit), rules["ev_custom"], 0, ev_stat_limit, 85)
          if custom
            rules["ev_custom"] = custom
            rules["evs"] = value
          end
        else
          rules["evs"] = value if value
        end
      when 7
        value = choose_from(
          _INTL("Regla temporal de objetos equipados para los Pokemon del combate."),
          [_INTL("Por defecto"), _INTL("Aleatorios"), _INTL("Sin objeto"), _INTL("Recomendados")],
          ["default", "random", "none", "recommended"],
          rules["items"]
        )
        rules["items"] = value if value
      when 8
        value = choose_from(
          _INTL("Regla temporal de movimientos para los Pokemon del combate."),
          [_INTL("Recomendados"), _INTL("Por defecto"), _INTL("Aleatorios que pueda aprender"), _INTL("Aleatorios completos")],
          ["recommended", "default", "random_learnable", "random_any"],
          rules["moves"]
        )
        rules["moves"] = value if value
      when 9
        value = choose_from(
          _INTL("Regla temporal de megaevolucion o forma especial del equipo."),
          [_INTL("Por defecto"), _INTL("Mega aleatoria")],
          ["default", "random"],
          rules["mega"]
        )
        rules["mega"] = value if value
      when 10
        save_rules(rules)
        request_rules = rules_for_request(rules)
        SebiVisualMultiplayer.request_action(player, "battle", mode, request_rules) if defined?(SebiVisualMultiplayer)
        return
      else
        return
      end
      save_rules(rules)
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir la solicitud de combate PvP."))
  end

  def self.safe(default_value = nil)
    return yield
  rescue Exception
    return default_value
  end

  def self.elapsed_ms(start_time)
    return ((Time.now - start_time) * 1000).to_i
  rescue Exception
    return 0
  end

  def self.pvp_prepare_log(message, session = nil)
    SebiVisualMultiplayer.pvp_log(message, session) if defined?(SebiVisualMultiplayer)
  rescue Exception
  end

  def self.clone_pokemon(pokemon)
    return nil if !pokemon
    return Marshal.load(Marshal.dump(pokemon))
  rescue Exception
    return nil
  end

  def self.valid_pokemon?(pokemon)
    return false if !pokemon
    return false if safe(false) { pokemon.isEgg? ? true : false }
    return true
  rescue Exception
    return false
  end

  def self.owned_refs
    return SebiBattleAdvisor.owned_pokemon_refs if defined?(SebiBattleAdvisor)
    return []
  rescue Exception
    return []
  end

  def self.highest_owned_level
    highest = 1
    for ref in owned_refs
      pokemon = ref["pokemon"] rescue nil
      next if !valid_pokemon?(pokemon)
      level = safe(1) { pokemon.level.to_i }
      highest = level if level > highest
    end
    return highest
  rescue Exception
    return 1
  end

  def self.party_max_level(party)
    highest = 1
    for pokemon in party
      next if !valid_pokemon?(pokemon)
      level = safe(1) { pokemon.level.to_i }
      highest = level if level > highest
    end
    return highest
  rescue Exception
    return 1
  end

  def self.constant_id(mod_name, name)
    return 0 if name == nil || name.to_s == ""
    mod = Object.const_get(mod_name.to_s) rescue nil
    return 0 if !mod
    names = [name.to_s, name.to_s.upcase]
    for text in names
      begin
        id = getID(mod, text.to_sym) if defined?(getID)
        return id.to_i if id && id.to_i > 0
      rescue Exception
      end
      begin
        id = mod.const_get(text.to_sym)
        return id.to_i if id && id.to_i > 0
      rescue Exception
      end
      begin
        id = mod.const_get(text)
        return id.to_i if id && id.to_i > 0
      rescue Exception
      end
    end
    return 0
  rescue Exception
    return 0
  end

  def self.species_id_set(symbols)
    @species_id_sets = {} if !@species_id_sets
    key = symbols.join("|")
    return @species_id_sets[key] if @species_id_sets.has_key?(key)
    ret = {}
    for symbol in symbols
      id = constant_id("PBSpecies", symbol)
      ret[id] = true if id.to_i > 0
    end
    @species_id_sets[key] = ret
    return ret
  rescue Exception
    return {}
  end

  def self.species_symbol_set(symbols)
    @species_symbol_sets = {} if !@species_symbol_sets
    key = symbols.join("|")
    return @species_symbol_sets[key] if @species_symbol_sets.has_key?(key)
    ret = {}
    for symbol in symbols
      ret[symbol.to_s.upcase.gsub(/[^A-Z0-9]/, "")] = true
    end
    @species_symbol_sets[key] = ret
    return ret
  rescue Exception
    return {}
  end

  def self.species_internal_name(species)
    species = species.to_i
    record = pbs_species_fast_index[species] rescue nil
    value = record["internalName"].to_s if record && record["internalName"]
    return value if value && value != ""
    if defined?(PBSpecies)
      for const_name in PBSpecies.constants
        id = PBSpecies.const_get(const_name) rescue 0
        return const_name.to_s if id.to_i == species
      end
    end
    return ""
  rescue Exception
    return ""
  end

  def self.special_non_legendary_species?(species)
    set = species_id_set(PVP_SPECIAL_NON_LEGENDARY_SYMBOLS)
    return set[species.to_i] ? true : false
  rescue Exception
    return false
  end

  def self.legendary_species?(species)
    @legend_cache = {} if !@legend_cache
    species = species.to_i
    return @legend_cache[species] if @legend_cache.has_key?(species)
    if special_non_legendary_species?(species)
      @legend_cache[species] = false
      return false
    end
    explicit = species_id_set(PVP_LEGENDARY_SYMBOLS)
    if explicit[species]
      @legend_cache[species] = true
      return true
    end
    symbol = species_internal_name(species).to_s.upcase.gsub(/[^A-Z0-9]/, "")
    value = species_symbol_set(PVP_LEGENDARY_SYMBOLS)[symbol] ? true : false
    @legend_cache[species] = value
    return value
  rescue Exception
    return false
  end

  def self.final_evolution_species?(species)
    @final_evolution_cache = {} if !@final_evolution_cache
    species = species.to_i
    return @final_evolution_cache[species] if @final_evolution_cache.has_key?(species)
    evolutions = pbGetEvolvedFormData(species) rescue []
    value = !evolutions || evolutions.length == 0
    @final_evolution_cache[species] = value
    return value
  rescue Exception
    return false
  end

  def self.pokemon_has_type?(pokemon, type)
    return true if type.to_i < 0
    return pokemon.hasType?(type.to_i) if pokemon && pokemon.respond_to?(:hasType?)
    return false
  rescue Exception
    return false
  end

  def self.entry_pokemon(entry)
    return entry["pokemon"] if entry.is_a?(Hash)
    return entry
  rescue Exception
    return nil
  end

  def self.entry_species(entry)
    return entry.to_i if entry.is_a?(Numeric)
    return entry["species"].to_i if entry.is_a?(Hash) && entry["species"]
    pokemon = entry_pokemon(entry)
    return pokemon.species.to_i if pokemon
    return entry.to_i
  rescue Exception
    return 0
  end

  def self.shuffle_array(array)
    ret = array.clone
    i = ret.length - 1
    while i > 0
      j = rand(i + 1)
      ret[i], ret[j] = ret[j], ret[i]
      i -= 1
    end
    return ret
  rescue Exception
    return array
  end

  def self.pick_entries(pool, count)
    return shuffle_array(pool)[0, count]
  rescue Exception
    return []
  end

  def self.legend_target(rules)
    count = rules["legends"].to_i
    count = 0 if count < 0
    count = TEAM_SIZE if count > TEAM_SIZE
    return count
  end

  def self.legend_rule_generated_source?(rules)
    source = normalize_rules(rules)["source"].to_s
    return ["owned", "random", "teams", "ai"].include?(source)
  rescue Exception
    return false
  end

  def self.party_legend_count(party)
    count = 0
    for pokemon in (party || [])
      next if !pokemon
      count += 1 if legendary_species?(pokemon.species)
    end
    return count
  rescue Exception
    return 0
  end

  def self.party_legend_names(party)
    names = []
    for pokemon in (party || [])
      next if !pokemon
      next if !legendary_species?(pokemon.species)
      name = PBSpecies.getName(pokemon.species).to_s rescue pokemon.name.to_s
      names.push(name) if name && name != ""
    end
    return names.join(",")
  rescue Exception
    return ""
  end

  def self.validate_generated_party_rules(party, rules)
    return nil if !legend_rule_generated_source?(rules)
    if !party || party.length < TEAM_SIZE
      return _INTL("No se pudo crear un equipo completo con las reglas elegidas ({1}/6).", party ? party.length : 0)
    end
    expected = legend_target(rules)
    actual = party_legend_count(party)
    if actual != expected
      return _INTL("La regla pide {1} legendarios, pero el equipo preparado tiene {2}. Reintenta o cambia origen/monotipo.", expected, actual)
    end
    return nil
  rescue Exception
    return _INTL("No se pudo validar la regla de legendarios del equipo.")
  end

  def self.pick_with_legend_count(pool, rules)
    legends = []
    normal = []
    for entry in pool
      if legendary_species?(entry_species(entry))
        legends.push(entry)
      elsif special_non_legendary_species?(entry_species(entry))
        next
      else
        normal.push(entry)
      end
    end
    legend_count = legend_target(rules)
    normal_count = TEAM_SIZE - legend_count
    if legends.length < legend_count
      return [nil, _INTL("No hay suficientes Pokemon legendarios validos para esta regla.")]
    end
    if normal.length < normal_count
      return [nil, _INTL("No hay suficientes Pokemon no legendarios validos para esta regla.")]
    end
    selected = pick_entries(legends, legend_count) + pick_entries(normal, normal_count)
    return [shuffle_array(selected), nil]
  rescue Exception
    return [nil, _INTL("No se pudo seleccionar el equipo con la regla de legendarios.")]
  end

  def self.heal_party(party)
    for pokemon in party
      next if !pokemon
      pokemon.calcStats if pokemon.respond_to?(:calcStats)
      pokemon.heal if pokemon.respond_to?(:heal)
    end
    return party
  rescue Exception
    return party
  end

  def self.current_party
    ret = []
    return ret if !$Trainer || !$Trainer.party
    for pokemon in $Trainer.party
      next if !valid_pokemon?(pokemon)
      copy = clone_pokemon(pokemon)
      ret.push(copy) if copy
    end
    return ret
  rescue Exception
    return []
  end

  def self.owned_random_party(rules)
    pool = []
    type = rules["type"].to_i
    for ref in owned_refs
      pokemon = ref["pokemon"] rescue nil
      next if !valid_pokemon?(pokemon)
      next if !pokemon_has_type?(pokemon, type)
      pool.push(ref)
    end
    selected, error = pick_with_legend_count(pool, rules)
    return [nil, error] if error
    party = []
    for ref in selected
      copy = clone_pokemon(ref["pokemon"])
      party.push(copy) if copy
    end
    return [nil, _INTL("No se pudo crear un equipo completo con tus Pokemon ({1}/6).", party.length)] if party.length < TEAM_SIZE
    return [party, nil]
  rescue Exception
    return [nil, _INTL("No se pudo preparar un equipo aleatorio de tus Pokemon.")]
  end

  def self.owned_species
    ret = {}
    for ref in owned_refs
      pokemon = ref["pokemon"] rescue nil
      next if !valid_pokemon?(pokemon)
      ret[pokemon.species.to_i] = true
    end
    return ret
  rescue Exception
    return {}
  end

  def self.pbs_pokemon_path
    return File.join(pbs_dir, "pokemon.txt")
  rescue Exception
    return "PBS/pokemon.txt"
  end

  def self.pbs_species_fast_index
    return @pvp_pbs_species_fast_index if @pvp_pbs_species_fast_index
    records = {}
    internal_to_id = {}
    current_id = 0
    path = pbs_pokemon_path
    if FileTest.exist?(path)
      File.open(path, "rb") do |file|
        file.each_line do |line|
          text = line.to_s.gsub(/\r|\n/, "").strip
          next if text == "" || text[0, 1] == "#"
          if text =~ /^\[(\d+)\]/
            current_id = $1.to_i
            records[current_id] = { "types" => [], "evolutionNames" => [] }
          elsif current_id > 0 && text =~ /^InternalName=(.+)$/i
            internal_name = $1.to_s.strip.upcase
            internal_to_id[internal_name] = current_id
            records[current_id]["internalName"] = internal_name if records[current_id]
          elsif current_id > 0 && text =~ /^Type1=(.+)$/i
            type = constant_id("PBTypes", $1.to_s.strip)
            records[current_id]["types"].push(type) if type.to_i >= 0
          elsif current_id > 0 && text =~ /^Type2=(.+)$/i
            type = constant_id("PBTypes", $1.to_s.strip)
            records[current_id]["types"].push(type) if type.to_i >= 0 && !records[current_id]["types"].include?(type.to_i)
          elsif current_id > 0 && text =~ /^Evolutions=(.*)$/i
            parts = $1.to_s.split(",")
            i = 0
            while i < parts.length
              name = parts[i].to_s.strip.upcase
              records[current_id]["evolutionNames"].push(name) if name != ""
              i += 3
            end
          end
        end
      end
    end
    for species, record in records
      evolutions = []
      for name in (record["evolutionNames"] || [])
        id = internal_to_id[name].to_i
        id = constant_id("PBSpecies", name) if id <= 0
        evolutions.push(id) if id.to_i > 0 && !evolutions.include?(id.to_i)
      end
      record["evolutions"] = evolutions
    end
    @pvp_pbs_species_fast_index = records
    return @pvp_pbs_species_fast_index
  rescue Exception
    @pvp_pbs_species_fast_index = records || {}
    return @pvp_pbs_species_fast_index
  end

  def self.fast_species_type_ids(species)
    record = pbs_species_fast_index[species.to_i]
    return record["types"] if record && record["types"] && record["types"].length > 0
    pokemon = safe(nil) { PokeBattle_Pokemon.new(species.to_i, 1, $Trainer) }
    return pokemon_type_ids_for_role(pokemon) if pokemon
    return []
  rescue Exception
    return []
  end

  def self.fast_final_evolution_species?(species)
    record = pbs_species_fast_index[species.to_i]
    return (record["evolutions"] || []).length == 0 if record
    return final_evolution_species?(species)
  rescue Exception
    return false
  end

  def self.species_has_type_id?(species, type)
    return true if type.to_i < 0
    return fast_species_type_ids(species).include?(type.to_i)
  rescue Exception
    return false
  end

  def self.random_species_pool(rules)
    ret = []
    owned = owned_species
    type = rules["type"].to_i
    max = PBSpecies.maxValue rescue 0
    for species in 1..max
      next if owned[species]
      next if !fast_final_evolution_species?(species)
      next if special_non_legendary_species?(species)
      next if !species_has_type_id?(species, type)
      ret.push(species)
    end
    return ret
  rescue Exception
    return ret || []
  end

  def self.pbs_dir
    root = File.dirname(SebiVisualMultiplayer.multiplayer_dir) if defined?(SebiVisualMultiplayer)
    root = File.dirname(File.dirname(File.expand_path(__FILE__))) if !root || root.to_s == ""
    return File.join(root, "PBS")
  rescue Exception
    return "PBS"
  end

  def self.usage_set_paths
    ret = []
    dir = pbs_dir
    for filename in PVP_USAGE_SET_FILES
      path = File.join(dir, filename)
      ret.push(path) if FileTest.exist?(path)
    end
    return ret
  rescue Exception
    return []
  end

  def self.parse_set_stat_indexes(text)
    ret = []
    text.to_s.split(",").each do |part|
      key = part.to_s.strip.upcase.gsub(/[^A-Z]/, "")
      index = PVP_SET_STAT_INDEXES[key]
      ret.push(index.to_i) if index != nil && !ret.include?(index.to_i)
    end
    return ret
  rescue Exception
    return []
  end

  def self.parse_set_moves(text)
    ret = []
    text.to_s.split(",").each do |part|
      id = constant_id("PBMoves", part.to_s.strip)
      ret.push(id) if id.to_i > 0 && !ret.include?(id.to_i)
      break if ret.length >= 4
    end
    return ret
  rescue Exception
    return []
  end

  def self.usage_sets
    return @usage_sets if @usage_sets
    ret = []
    for path in usage_set_paths
      File.open(path, "rb") do |file|
        file.each_line do |line|
          line = line.gsub(/\r|\n/, "").strip
          next if line == "" || line[0, 1] == "#"
          parts = line.split(";")
          next if parts.length < 5
          species = constant_id("PBSpecies", parts[0].to_s.strip)
          next if species.to_i <= 0
          moves = parse_set_moves(parts[4])
          next if moves.length == 0
          ret.push({
            "species" => species.to_i,
            "item" => constant_id("PBItems", parts[1].to_s.strip),
            "nature" => constant_id("PBNatures", parts[2].to_s.strip),
            "evStats" => parse_set_stat_indexes(parts[3]),
            "moves" => moves,
            "source" => File.basename(path)
          })
        end
      end
    end
    @usage_sets = ret
    return @usage_sets
  rescue Exception
    @usage_sets = ret || []
    return @usage_sets
  end

  def self.usage_sets_for_species(species)
    if @usage_sets_by_species
      return @usage_sets_by_species[species.to_i] || []
    end
    grouped = {}
    for set in usage_sets
      id = set["species"].to_i
      grouped[id] = [] if !grouped[id]
      grouped[id].push(set)
    end
    @usage_sets_by_species = grouped
    return @usage_sets_by_species[species.to_i] || []
  rescue Exception
    return []
  end

  def self.usage_sets_for_species_slow(species)
    ret = []
    for set in usage_sets
      ret.push(set) if set["species"].to_i == species.to_i
    end
    return ret
  rescue Exception
    return []
  end

  def self.random_usage_set_for_species(species)
    sets = usage_sets_for_species(species)
    return nil if sets.length == 0
    return sets[rand(sets.length)]
  rescue Exception
    return nil
  end

  def self.remember_usage_set(pokemon, set)
    pokemon.instance_variable_set(:@sebi_pvp_usage_set, set) if pokemon && set
  rescue Exception
  end

  def self.remembered_usage_set(pokemon)
    return pokemon.instance_variable_get(:@sebi_pvp_usage_set) if pokemon
  rescue Exception
    return nil
  end

  def self.usage_set_for_pokemon(pokemon)
    return nil if !pokemon
    set = remembered_usage_set(pokemon)
    return set if set
    set = random_usage_set_for_species(pokemon.species)
    remember_usage_set(pokemon, set)
    return set
  rescue Exception
    return nil
  end

  def self.assign_moves_from_ids(pokemon, move_ids)
    return false if !pokemon || !defined?(PBMove)
    ids = []
    for id in move_ids
      ids.push(id.to_i) if id.to_i > 0 && !ids.include?(id.to_i)
      break if ids.length >= 4
    end
    return false if ids.length == 0
    for i in 0...4
      pokemon.moves[i] = PBMove.new(ids[i].to_i) if ids[i]
      pokemon.moves[i] = PBMove.new(0) if !ids[i]
    end
    pokemon.firstmoves = ids if pokemon.respond_to?(:firstmoves=)
    return true
  rescue Exception
    return false
  end

  def self.usage_ev_values(pokemon, set)
    values = [0, 0, 0, 0, 0, 0]
    order = []
    for index in (set["evStats"] || [])
      order.push(index.to_i) if index.to_i >= 0 && index.to_i < 6 && !order.include?(index.to_i)
    end
    for index in strongest_stat_indexes(pokemon)
      order.push(index.to_i) if !order.include?(index.to_i)
    end
    remaining = ev_limit
    for index in order
      break if remaining <= 0
      amount = [ev_stat_limit, remaining].min
      values[index.to_i] = amount
      remaining -= amount
    end
    return values
  rescue Exception
    return recommended_ev_values(pokemon)
  end

  def self.apply_usage_set_to_pokemon(pokemon, include_item = false, include_evs = false)
    return false if !pokemon
    set = usage_set_for_pokemon(pokemon)
    return false if !set
    if pokemon.respond_to?(:natureflag=)
      pokemon.natureflag = set["nature"].to_i
    end
    assign_moves_from_ids(pokemon, set["moves"] || [])
    set_temporary_item(pokemon, set["item"].to_i) if include_item && set["item"].to_i > 0
    pokemon.ev = usage_ev_values(pokemon, set) if include_evs && pokemon.respond_to?(:ev=)
    pokemon.calcStats if pokemon.respond_to?(:calcStats)
    return true
  rescue Exception
    return false
  end

  def self.usage_team_set_pool(rules)
    grouped = {}
    type = rules["type"].to_i
    for set in usage_sets
      species = set["species"].to_i
      next if species <= 0
      next if special_non_legendary_species?(species)
      next if !fast_final_evolution_species?(species)
      next if !species_has_type_id?(species, type)
      grouped[species] = [] if !grouped[species]
      grouped[species].push(set)
    end
    ret = []
    grouped.each_value do |sets|
      ret.push(sets[rand(sets.length)]) if sets.length > 0
    end
    return ret
  rescue Exception
    return []
  end

  def self.total_random_party(rules)
    selected, error = pick_with_legend_count(random_species_pool(rules), rules)
    return [nil, error] if error
    party = []
    level = highest_owned_level
    for species in selected
      pokemon = safe(nil) { PokeBattle_Pokemon.new(species.to_i, level, $Trainer) }
      next if !pokemon
      pokemon.resetMoves if pokemon.respond_to?(:resetMoves)
      remember_usage_set(pokemon, random_usage_set_for_species(species.to_i))
      party.push(pokemon)
    end
    return [nil, _INTL("No se pudo crear un equipo aleatorio total completo ({1}/6).", party.length)] if party.length < TEAM_SIZE
    return [party, nil]
  rescue Exception
    return [nil, _INTL("No se pudo preparar el equipo aleatorio total.")]
  end

  def self.random_usage_team_party(rules)
    selected, error = pick_with_legend_count(usage_team_set_pool(rules), rules)
    return [nil, error] if error
    party = []
    level = highest_owned_level
    for set in selected
      pokemon = safe(nil) { PokeBattle_Pokemon.new(set["species"].to_i, level, $Trainer) }
      next if !pokemon
      pokemon.resetMoves if pokemon.respond_to?(:resetMoves)
      remember_usage_set(pokemon, set)
      apply_usage_set_to_pokemon(pokemon, true, true)
      party.push(pokemon)
    end
    return [nil, _INTL("No se pudo crear un equipo random completo con los sets disponibles.")] if party.length < TEAM_SIZE
    return [party, nil]
  rescue Exception
    return [nil, _INTL("No se pudo preparar el equipo random de sets.")]
  end

  def self.saved_team_party(rules)
    return [nil, _INTL("El gestor de equipos guardados no esta disponible.")] if !defined?(SebiSavedTeams)
    team = SebiSavedTeams.team_by_name(rules["saved_team"].to_s)
    if !team
      team = SebiSavedTeams.choose_team(_INTL("Elige el equipo Showdown para este combate."))
      return [nil, _INTL("No se eligio ningun equipo guardado.")] if !team
      rules["saved_team"] = team["name"].to_s
    end
    party, error = SebiSavedTeams.party_from_team(team, false)
    return [nil, error] if error
    return [party, nil]
  rescue Exception
    return [nil, _INTL("No se pudo preparar el equipo guardado.")]
  end

  def self.ai_team_refs
    ret = []
    return ret if !defined?(SebiBattleAdvisor)
    path = SebiBattleAdvisor.pvp_ai_team_path
    return ret if !FileTest.exist?(path)
    File.open(path, "rb") do |file|
      file.each_line do |line|
        line = line.gsub(/\r|\n/, "").strip
        next if line == "" || line[0, 1] == "#"
        parts = line.split("|")
        next if parts.length < 2
        if parts[0].to_s == "party"
          ret.push({ "loc" => "party", "index" => parts[1].to_i, "box" => -1, "slot" => -1 })
        elsif parts[0].to_s == "box" && parts.length >= 3
          ret.push({ "loc" => "box", "index" => -1, "box" => parts[1].to_i, "slot" => parts[2].to_i })
        end
      end
    end
    return ret
  rescue Exception
    return []
  end

  def self.resolve_ai_ref(ref)
    if ref["loc"] == "party"
      return nil if !$Trainer || !$Trainer.party
      return $Trainer.party[ref["index"].to_i]
    end
    return nil if !defined?($PokemonStorage) || !$PokemonStorage
    return $PokemonStorage[ref["box"].to_i, ref["slot"].to_i]
  rescue Exception
    return nil
  end

  def self.ai_party(rules)
    refs = ai_team_refs
    if refs.length == 0
      return [nil, _INTL("No hay equipo PvP de IA preparado. Usa F12 > IA > Preparar equipo PvP IA.")]
    end
    party = []
    seen = {}
    for ref in refs
      key = ref["loc"].to_s + ":" + ref["index"].to_i.to_s + ":" + ref["box"].to_i.to_s + ":" + ref["slot"].to_i.to_s
      next if seen[key]
      seen[key] = true
      pokemon = resolve_ai_ref(ref)
      next if !valid_pokemon?(pokemon)
      copy = clone_pokemon(pokemon)
      party.push(copy) if copy
      break if party.length >= TEAM_SIZE
    end
    return [nil, _INTL("El equipo PvP de IA ya no apunta a 6 Pokemon validos. Vuelve a prepararlo.")] if party.length < TEAM_SIZE
    type = rules["type"].to_i
    for pokemon in party
      if !pokemon_has_type?(pokemon, type)
        return [nil, _INTL("El equipo PvP de IA no cumple el monotipo configurado.")]
      end
    end
    legend_count = 0
    for pokemon in party
      legend_count += 1 if legendary_species?(pokemon.species)
    end
    if legend_count != legend_target(rules)
      return [nil, _INTL("El equipo PvP de IA no cumple la cantidad de legendarios configurada.")]
    end
    return [party, nil]
  rescue Exception
    return [nil, _INTL("No se pudo cargar el equipo PvP elegido por IA.")]
  end

  def self.raw_base_stats(pokemon)
    stats = safe(nil) { pokemon.baseStats }
    return stats if stats && stats.length >= 6
    return [0, 0, 0, 0, 0, 0]
  rescue Exception
    return [0, 0, 0, 0, 0, 0]
  end

  def self.strongest_stat_indexes(pokemon)
    stats = raw_base_stats(pokemon)
    indexes = [0, 1, 2, 3, 4, 5]
    indexes.sort! do |a, b|
      compare = stats[b].to_i <=> stats[a].to_i
      compare = a.to_i <=> b.to_i if compare == 0
      compare
    end
    return indexes
  rescue Exception
    return [0, 1, 2, 3, 4, 5]
  end

  def self.ev_limit
    return PokeBattle_Pokemon::EVLIMIT if defined?(PokeBattle_Pokemon) && PokeBattle_Pokemon.const_defined?(:EVLIMIT)
    return 510
  rescue Exception
    return 510
  end

  def self.ev_stat_limit
    return PokeBattle_Pokemon::EVSTATLIMIT if defined?(PokeBattle_Pokemon) && PokeBattle_Pokemon.const_defined?(:EVSTATLIMIT)
    return 252
  rescue Exception
    return 252
  end

  def self.random_ev_values
    values = [0, 0, 0, 0, 0, 0]
    total = ev_limit
    for i in 0...values.length
      break if total <= 0
      values[i] = 1
      total -= 1
    end
    while total > 0
      available = []
      for i in 0...values.length
        available.push(i) if values[i].to_i < ev_stat_limit
      end
      break if available.length == 0
      index = available[rand(available.length)]
      values[index] += 1
      total -= 1
    end
    return values
  rescue Exception
    return [85, 85, 85, 85, 85, 85]
  end

  def self.recommended_ev_values(pokemon)
    values = [0, 0, 0, 0, 0, 0]
    indexes = strongest_stat_indexes(pokemon)
    remaining = ev_limit
    for index in indexes
      break if remaining <= 0
      amount = [ev_stat_limit, remaining].min
      values[index.to_i] = amount
      remaining -= amount
    end
    return values
  rescue Exception
    return [85, 85, 85, 85, 85, 85]
  end

  def self.recommended_iv_values(pokemon)
    values = [0, 0, 0, 0, 0, 0]
    ranked_values = [31, 31, 25, 20, 15, 10]
    indexes = strongest_stat_indexes(pokemon)
    for i in 0...indexes.length
      values[indexes[i].to_i] = ranked_values[i].to_i
    end
    return values
  rescue Exception
    return [31, 31, 25, 20, 15, 10]
  end

  def self.attack_role(pokemon)
    stats = raw_base_stats(pokemon)
    attack = stats[1].to_i
    special = stats[4].to_i
    return "mixed" if attack <= 0 && special <= 0
    return "physical" if attack >= special + 18 || attack * 100 >= special * 120
    return "special" if special >= attack + 18 || special * 100 >= attack * 120
    return "mixed"
  rescue Exception
    return "mixed"
  end

  def self.move_data_for_id(move_id)
    id = move_id.to_i
    return nil if id <= 0 || !defined?(PBMoveData)
    @pvp_move_data_cache = {} if !@pvp_move_data_cache
    return @pvp_move_data_cache[id] if @pvp_move_data_cache.has_key?(id)
    @pvp_move_data_cache[id] = PBMoveData.new(id)
    return @pvp_move_data_cache[id]
  rescue Exception
    return nil
  end

  def self.move_category_for_id(move_id)
    data = move_data_for_id(move_id)
    return 2 if !data
    return data.category.to_i
  rescue Exception
    return 2
  end

  def self.move_power_for_id(move_id)
    data = move_data_for_id(move_id)
    return 0 if !data
    power = data.basedamage.to_i
    return 80 if power == 1
    return power
  rescue Exception
    return 0
  end

  def self.move_accuracy_for_id(move_id)
    data = move_data_for_id(move_id)
    return 100 if !data
    acc = data.accuracy.to_i
    return 100 if acc <= 0
    return acc
  rescue Exception
    return 100
  end

  def self.move_type_for_id(move_id)
    data = move_data_for_id(move_id)
    return -1 if !data
    return data.type.to_i
  rescue Exception
    return -1
  end

  def self.pokemon_type_ids_for_role(pokemon)
    ret = []
    type1 = safe(-1) { pokemon.type1.to_i }
    type2 = safe(type1) { pokemon.type2.to_i }
    ret.push(type1) if type1 >= 0
    ret.push(type2) if type2 >= 0 && type2 != type1
    return ret
  rescue Exception
    return []
  end

  def self.same_type_attack?(pokemon, move_id)
    type = move_type_for_id(move_id)
    return false if type < 0
    return pokemon_type_ids_for_role(pokemon).include?(type)
  rescue Exception
    return false
  end

  def self.role_compatible_move?(pokemon, move_id, allow_status = true)
    category = move_category_for_id(move_id)
    power = move_power_for_id(move_id)
    return allow_status if power <= 0 || category > 1
    role = attack_role(pokemon)
    return true if role == "mixed"
    return category == 0 if role == "physical"
    return category == 1 if role == "special"
    return true
  rescue Exception
    return true
  end

  def self.move_score(pokemon, move_id)
    data = move_data_for_id(move_id)
    return -9999 if !data
    power = move_power_for_id(move_id)
    accuracy = move_accuracy_for_id(move_id)
    category = data.category.to_i
    role = attack_role(pokemon)
    score = 0
    if power > 0 && category <= 1
      score += power
      score += 35 if same_type_attack?(pokemon, move_id)
      score += [[accuracy, 100].min, 50].max / 5
      if role == "physical"
        score += category == 0 ? 55 : -65
      elsif role == "special"
        score += category == 1 ? 55 : -65
      else
        score += 25
      end
    else
      score += 38
      score += 12 if role != "mixed"
    end
    return score
  rescue Exception
    return 0
  end

  def self.valid_move_id_for_pvp?(move_id)
    return false if move_id.to_i <= 0
    data = move_data_for_id(move_id)
    return false if !data
    name = PBMoves.getName(move_id.to_i).to_s rescue ""
    return false if name == "" || name == "???"
    return true
  rescue Exception
    return false
  end

  def self.all_move_ids
    return @all_pvp_move_ids if @all_pvp_move_ids
    ret = []
    if defined?(PBMoves)
      max = PBMoves.maxValue rescue 0
      if max && max.to_i > 0
        for id in 1..max.to_i
          ret.push(id) if valid_move_id_for_pvp?(id)
        end
      else
        for name in PBMoves.constants
          id = PBMoves.const_get(name) rescue 0
          ret.push(id.to_i) if valid_move_id_for_pvp?(id)
        end
      end
    end
    if ret.length == 0 && defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:move_list)
      for entry in SebiSaveEditor.move_list
        id = entry["id"].to_i rescue 0
        ret.push(id) if valid_move_id_for_pvp?(id)
      end
    end
    @all_pvp_move_ids = ret.uniq
    return @all_pvp_move_ids
  rescue Exception
    return []
  end

  def self.learnable_move_ids_for_pvp(pokemon, include_compatible = false)
    ret = []
    return ret if !pokemon
    @pvp_learnable_move_cache = {} if !@pvp_learnable_move_cache
    key = pokemon.species.to_i.to_s + ":" + pokemon.level.to_i.to_s + ":" + (include_compatible ? "1" : "0")
    if @pvp_learnable_move_cache.has_key?(key)
      ret += @pvp_learnable_move_cache[key]
    else
      base = []
      if defined?(SebiSaveEditor) && include_compatible
        base += SebiSaveEditor.compatible_move_ids(pokemon.species) if SebiSaveEditor.respond_to?(:compatible_move_ids)
      end
      list = safe([]) { pokemon.getMoveList }
      for entry in list
        if entry.is_a?(Array)
          level = entry[0].to_i
          move_id = entry[1].to_i
          base.push(move_id) if move_id > 0 && (level <= 0 || level <= pokemon.level.to_i)
        else
          move_id = entry.to_i
          base.push(move_id) if move_id > 0
        end
      end
      @pvp_learnable_move_cache[key] = base.uniq.select { |id| valid_move_id_for_pvp?(id) }
      ret += @pvp_learnable_move_cache[key]
    end
    for move in (pokemon.moves rescue [])
      id = safe(0) { move.id.to_i }
      ret.push(id) if id > 0
    end
    return ret.uniq.select { |id| valid_move_id_for_pvp?(id) }
  rescue Exception
    return []
  end

  def self.usage_move_ids_for_pvp(pokemon)
    set = usage_set_for_pokemon(pokemon)
    return [] if !set
    return (set["moves"] || []).select { |id| valid_move_id_for_pvp?(id) }
  rescue Exception
    return []
  end

  def self.select_best_move_ids(pokemon, candidates, randomize = false)
    ids = (candidates || []).uniq.select { |id| valid_move_id_for_pvp?(id) }
    return [] if ids.length == 0
    compatible = ids.select { |id| role_compatible_move?(pokemon, id, true) }
    ids = compatible if compatible.length >= 4
    scored = ids.collect { |id| [id, move_score(pokemon, id)] }
    scored.sort! { |a, b| b[1] <=> a[1] }
    if randomize
      scored = shuffle_array(scored[0, [scored.length, 18].min])
    end
    selected = []
    used_type_category = {}
    status_count = 0
    for pair in scored
      id = pair[0].to_i
      category = move_category_for_id(id)
      power = move_power_for_id(id)
      is_status = power <= 0 || category > 1
      next if is_status && status_count >= 1 && selected.length < 3
      key = move_type_for_id(id).to_s + ":" + category.to_s
      next if used_type_category[key] && selected.length < 3
      selected.push(id)
      used_type_category[key] = true
      status_count += 1 if is_status
      break if selected.length >= 4
    end
    if selected.length < 4
      for pair in scored
        id = pair[0].to_i
        next if selected.include?(id)
        selected.push(id)
        break if selected.length >= 4
      end
    end
    return selected
  rescue Exception
    return []
  end

  def self.recommended_move_ids(pokemon)
    usage_candidates = usage_move_ids_for_pvp(pokemon)
    selected = select_best_move_ids(pokemon, usage_candidates, false)
    return selected if selected.length >= 4
    candidates = usage_candidates + learnable_move_ids_for_pvp(pokemon, false)
    selected = select_best_move_ids(pokemon, candidates, false)
    if selected.length < 4
      selected = select_best_move_ids(pokemon, candidates + all_move_ids, false)
    end
    return selected
  rescue Exception
    return []
  end

  def self.random_learnable_move_ids(pokemon)
    return select_best_move_ids(pokemon, learnable_move_ids_for_pvp(pokemon, true), true)
  rescue Exception
    return []
  end

  def self.random_any_move_ids(pokemon)
    return select_best_move_ids(pokemon, all_move_ids, true)
  rescue Exception
    return []
  end

  def self.apply_move_rule(pokemon, rule)
    return if !pokemon || rule.to_s == "default"
    ids = []
    ids = recommended_move_ids(pokemon) if rule.to_s == "recommended"
    ids = random_learnable_move_ids(pokemon) if rule.to_s == "random_learnable"
    ids = random_any_move_ids(pokemon) if rule.to_s == "random_any"
    assign_moves_from_ids(pokemon, ids) if ids && ids.length > 0
  rescue Exception
  end

  def self.apply_iv_rule(pokemon, rule, custom_value = nil)
    return if !pokemon || rule.to_s == "default"
    values = nil
    values = [rand(32), rand(32), rand(32), rand(32), rand(32), rand(32)] if rule.to_s == "random"
    values = [16, 16, 16, 16, 16, 16] if rule.to_s == "balanced"
    values = [0, 0, 0, 0, 0, 0] if rule.to_s == "zero"
    values = recommended_iv_values(pokemon) if rule.to_s == "recommended"
    if rule.to_s == "custom"
      value = clamp_int(custom_value, 0, 31, 31)
      values = [value, value, value, value, value, value]
    end
    pokemon.iv = values if values && pokemon.respond_to?(:iv=)
  rescue Exception
  end

  def self.apply_ev_rule(pokemon, rule, custom_value = nil)
    return if !pokemon || rule.to_s == "default"
    values = nil
    values = random_ev_values if rule.to_s == "random"
    values = [85, 85, 85, 85, 85, 85] if rule.to_s == "balanced"
    values = [0, 0, 0, 0, 0, 0] if rule.to_s == "zero"
    values = recommended_ev_values(pokemon) if rule.to_s == "recommended"
    if rule.to_s == "custom"
      value = clamp_int(custom_value, 0, ev_stat_limit, 85)
      values = [value, value, value, value, value, value]
    end
    pokemon.ev = values if values && pokemon.respond_to?(:ev=)
  rescue Exception
  end

  def self.item_id(symbol)
    return 0 if !defined?(PBItems)
    id = constant_id("PBItems", symbol)
    return id.to_i if id.to_i > 0
    value = getConst(PBItems, symbol) rescue nil
    return value.to_i if value
    return 0
  rescue Exception
    return 0
  end

  def self.item_symbol_for_id(item_id_value)
    @pvp_item_symbol_cache = {} if !@pvp_item_symbol_cache
    id = item_id_value.to_i
    return @pvp_item_symbol_cache[id] if @pvp_item_symbol_cache.has_key?(id)
    if defined?(PBItems)
      for name in PBItems.constants
        value = PBItems.const_get(name) rescue nil
        next if value == nil
        if value.to_i == id
          @pvp_item_symbol_cache[id] = name.to_s.upcase
          return @pvp_item_symbol_cache[id]
        end
      end
    end
    @pvp_item_symbol_cache[id] = ""
    return ""
  rescue Exception
    return ""
  end

  def self.csv_fields(line)
    fields = []
    current = ""
    quoted = false
    i = 0
    text = line.to_s.strip
    while i < text.length
      char = text[i, 1]
      if char == "\""
        if quoted && text[i + 1, 1] == "\""
          current += "\""
          i += 1
        else
          quoted = !quoted
        end
      elsif char == "," && !quoted
        fields.push(current)
        current = ""
      else
        current += char
      end
      i += 1
    end
    fields.push(current)
    return fields
  rescue Exception
    return []
  end

  def self.lookup_key(text)
    return text.to_s.downcase.gsub(/[^a-z0-9]/, "")
  rescue Exception
    return ""
  end

  def self.species_lookup
    return @pvp_species_lookup if @pvp_species_lookup
    ret = {}
    if defined?(PBSpecies)
      for const_name in PBSpecies.constants
        id = PBSpecies.const_get(const_name) rescue 0
        next if id.to_i <= 0
        ret[lookup_key(const_name.to_s)] = id.to_i
        name = PBSpecies.getName(id.to_i).to_s rescue ""
        ret[lookup_key(name)] = id.to_i if name && name != ""
      end
    end
    path = File.join(pbs_dir, "pokemon.txt")
    if FileTest.exist?(path)
      current_id = 0
      File.open(path, "rb") do |file|
        file.each_line do |line|
          text = line.to_s.strip
          if text =~ /^\[(\d+)\]/
            current_id = $1.to_i
          elsif current_id > 0 && text =~ /^Name=(.+)$/i
            ret[lookup_key($1)] = current_id
          elsif current_id > 0 && text =~ /^InternalName=(.+)$/i
            ret[lookup_key($1)] = current_id
          end
        end
      end
    end
    @pvp_species_lookup = ret
    return @pvp_species_lookup
  rescue Exception
    @pvp_species_lookup = ret || {}
    return @pvp_species_lookup
  end

  def self.extract_mega_species_names(description)
    text = description.to_s
    value = nil
    if text =~ /megaevolucionar\s+a\s+(.+?)(?:\.|$)/i
      value = $1.to_s
    elsif text =~ /megaevoluciona\s+a\s+(.+?)(?:\.|$)/i
      value = $1.to_s
    end
    return [] if !value || value == ""
    value = value.gsub(/ en combate/i, "")
    value = value.gsub(/\s+e\s+/i, ",")
    value = value.gsub(/\s+y\s+/i, ",")
    names = []
    for part in value.split(",")
      name = part.to_s.strip.gsub(/\.$/, "")
      names.push(name) if name != ""
    end
    return names
  rescue Exception
    return []
  end

  def self.mega_stone_species_map
    return @pvp_mega_stone_species_map if @pvp_mega_stone_species_map
    ret = {}
    lookup = species_lookup
    path = File.join(pbs_dir, "items.txt")
    if FileTest.exist?(path)
      File.open(path, "rb") do |file|
        file.each_line do |line|
          next if line.to_s.strip == "" || line.to_s.strip[0, 1] == "#"
          fields = csv_fields(line)
          next if fields.length < 7
          next if fields[4].to_i != 6
          description = fields[6].to_s
          next if description !~ /megaevolucionar/i && description !~ /megaevoluciona/i
          item = item_id(fields[1].to_s)
          next if item.to_i <= 0
          for name in extract_mega_species_names(description)
            species = lookup[lookup_key(name)].to_i
            next if species <= 0
            ret[species] = [] if !ret[species]
            ret[species].push({ "item" => item, "form" => nil }) if !ret[species].detect { |entry| entry["item"].to_i == item.to_i }
          end
        end
      end
    end
    @pvp_mega_stone_species_map = ret
    return @pvp_mega_stone_species_map
  rescue Exception
    @pvp_mega_stone_species_map = ret || {}
    return @pvp_mega_stone_species_map
  end

  def self.special_mega_item_species_map
    return @pvp_special_mega_item_species_map if @pvp_special_mega_item_species_map
    specs = [
      ["DIALGA", "ADAMANTORB", nil],
      ["PALKIA", "LUSTROUSORB", nil],
      ["GIRATINA", "GRISEOUSORB", 1],
      ["GROUDON", "REDORB", nil],
      ["KYOGRE", "BLUEORB", nil]
    ]
    ret = {}
    for spec in specs
      species = constant_id("PBSpecies", spec[0])
      item = item_id(spec[1])
      next if species.to_i <= 0 || item.to_i <= 0
      ret[species.to_i] = [] if !ret[species.to_i]
      ret[species.to_i].push({ "item" => item.to_i, "form" => spec[2] })
    end
    @pvp_special_mega_item_species_map = ret
    return @pvp_special_mega_item_species_map
  rescue Exception
    @pvp_special_mega_item_species_map = ret || {}
    return @pvp_special_mega_item_species_map
  end

  def self.mega_options_for_species(species)
    ret = []
    for entry in (mega_stone_species_map[species.to_i] || [])
      ret.push(entry)
    end
    for entry in (special_mega_item_species_map[species.to_i] || [])
      ret.push(entry) if !ret.detect { |existing| existing["item"].to_i == entry["item"].to_i }
    end
    return ret
  rescue Exception
    return []
  end

  def self.mega_options_for_pokemon(pokemon)
    return [] if !pokemon
    return mega_options_for_species(pokemon.species)
  rescue Exception
    return []
  end

  def self.mega_item_ids
    ret = {}
    mega_stone_species_map.each_value do |entries|
      for entry in entries
        ret[entry["item"].to_i] = true if entry["item"].to_i > 0
      end
    end
    special_mega_item_species_map.each_value do |entries|
      for entry in entries
        ret[entry["item"].to_i] = true if entry["item"].to_i > 0
      end
    end
    return ret
  rescue Exception
    return {}
  end

  def self.battle_item_pool
    symbols = [
      :LEFTOVERS, :LIFEORB, :CHOICEBAND, :CHOICESCARF, :CHOICESPECS,
      :EXPERTBELT, :FOCUSSASH, :FOCUSBAND, :SHELLBELL, :QUICKCLAW,
      :WHITEHERB, :POWERHERB, :MENTALHERB, :LUMBERRY, :SITRUSBERRY,
      :WIDELENS, :SCOPELENS, :BRIGHTPOWDER, :LIGHTCLAY, :ROCKYHELMET,
      :AIRBALLOON, :WEAKNESSPOLICY, :ASSAULTVEST, :MUSCLEBAND,
      :WISEGLASSES, :SALACBERRY, :LIECHIBERRY, :PETAYABERRY, :APICOTBERRY,
      :CHESTOBERRY, :FIGYBERRY, :WIKIBERRY, :MAGOBERRY, :AGUAVBERRY,
      :IAPAPABERRY, :KINGSROCK
    ]
    ret = []
    for symbol in symbols
      id = item_id(symbol)
      ret.push(id) if id > 0
    end
    return ret
  rescue Exception
    return []
  end

  def self.move_role_counts(pokemon)
    physical = 0
    special = 0
    status = 0
    for move in (pokemon.moves rescue [])
      next if !move || (move.id.to_i rescue 0) <= 0
      data = PBMoveData.new(move.id) rescue nil
      if !data || data.basedamage.to_i <= 0
        status += 1
      elsif data.category.to_i == 0
        physical += 1
      elsif data.category.to_i == 1
        special += 1
      else
        status += 1
      end
    end
    return [physical, special, status]
  rescue Exception
    return [0, 0, 0]
  end

  def self.type_symbol_for_id(type_id)
    @type_symbol_cache = {} if !@type_symbol_cache
    return @type_symbol_cache[type_id.to_i] if @type_symbol_cache.has_key?(type_id.to_i)
    if defined?(PBTypes)
      for name in PBTypes.constants
        value = PBTypes.const_get(name) rescue nil
        next if value == nil
        if value.to_i == type_id.to_i
          @type_symbol_cache[type_id.to_i] = name.to_s.upcase
          return @type_symbol_cache[type_id.to_i]
        end
      end
    end
    @type_symbol_cache[type_id.to_i] = ""
    return ""
  rescue Exception
    return ""
  end

  def self.type_boost_item_for_type(type_id)
    symbol = PVP_TYPE_ITEM_SYMBOLS[type_symbol_for_id(type_id)]
    return 0 if !symbol
    return item_id(symbol.to_sym)
  rescue Exception
    return 0
  end

  def self.pokemon_has_type_id?(pokemon, type_id)
    return pokemon_type_ids_for_role(pokemon).include?(type_id.to_i)
  rescue Exception
    return false
  end

  def self.move_type_counts_for_item(pokemon)
    ret = {}
    for move in (pokemon.moves rescue [])
      id = safe(0) { move.id.to_i }
      next if id <= 0
      next if move_power_for_id(id) <= 0
      type = move_type_for_id(id)
      next if type < 0
      ret[type] = 0 if !ret[type]
      ret[type] += 1
    end
    return ret
  rescue Exception
    return {}
  end

  def self.usage_item_reasonable?(pokemon, item_id_value, physical, special, status)
    id = item_id_value.to_i
    return false if id <= 0
    symbol = item_symbol_for_id(id)
    return false if symbol == ""
    damaging = physical.to_i + special.to_i
    counts = move_type_counts_for_item(pokemon)
    type_symbol = PVP_TYPE_ITEM_EXTRA_SYMBOLS[symbol]
    if !type_symbol
      for name, item_symbol in PVP_TYPE_ITEM_SYMBOLS
        if item_symbol.to_s.upcase == symbol
          type_symbol = name.to_s
          break
        end
      end
    end
    if type_symbol
      matched = false
      for type, count in counts
        matched = true if type_symbol_for_id(type) == type_symbol.to_s.upcase && count.to_i > 0
      end
      return matched
    end
    return false if symbol == "CHOICEBAND" && !(physical >= 3 && special == 0 && status == 0)
    return false if symbol == "CHOICESPECS" && !(special >= 3 && physical == 0 && status == 0)
    return false if symbol == "CHOICESCARF" && !(damaging >= 3 && status == 0)
    return false if symbol == "ASSAULTVEST" && !(damaging >= 4 && status == 0)
    return false if symbol == "MUSCLEBAND" && physical < 2
    return false if symbol == "WISEGLASSES" && special < 2
    return false if !PVP_REASONABLE_USAGE_ITEM_SYMBOLS.include?(symbol)
    return true
  rescue Exception
    return false
  end

  def self.recommended_item(pokemon)
    physical, special, status = move_role_counts(pokemon)
    damaging = physical + special
    stats = raw_base_stats(pokemon)
    hp = stats[0].to_i
    defense = stats[2].to_i
    speed = stats[3].to_i
    special_defense = stats[5].to_i
    bulk = hp + defense + special_defense
    role = attack_role(pokemon)
    candidates = []
    add_item = proc do |symbol, score|
      id = item_id(symbol)
      candidates.push([id, score.to_i]) if id.to_i > 0
    end
    usage_set = usage_set_for_pokemon(pokemon)
    usage_item = usage_set ? usage_set["item"].to_i : 0
    if usage_item_reasonable?(pokemon, usage_item, physical, special, status)
      candidates.push([usage_item, 84])
    end
    if pokemon_has_type_id?(pokemon, constant_id("PBTypes", "POISON"))
      add_item.call(:BLACKSLUDGE, 76 + bulk / 20)
    end
    add_item.call(:LEFTOVERS, 58 + bulk / 22 + status * 10)
    add_item.call(:SITRUSBERRY, 62 + bulk / 35) if bulk >= 210
    add_item.call(:LUMBERRY, 58 + damaging * 4) if damaging >= 2
    add_item.call(:CHESTOBERRY, 52 + bulk / 28) if bulk >= 230
    add_item.call(:LIFEORB, 66 + damaging * 5) if damaging >= 3
    add_item.call(:EXPERTBELT, 64 + move_type_counts_for_item(pokemon).keys.length * 5) if damaging >= 3
    add_item.call(:FOCUSSASH, 54 + speed / 5 - bulk / 35) if damaging >= 2
    add_item.call(:QUICKCLAW, 46 + bulk / 35 - speed / 12) if speed < 70 && damaging >= 2
    add_item.call(:SCOPELENS, 48 + damaging * 4) if damaging >= 3
    add_item.call(:KINGSROCK, 44 + speed / 9) if speed >= 90 && damaging >= 3
    add_item.call(:ROCKYHELMET, 58 + defense / 6) if defense >= 90
    add_item.call(:WEAKNESSPOLICY, 54 + bulk / 25) if bulk >= 240 && damaging >= 2
    add_item.call(:WIDELENS, 56) if damaging >= 3
    add_item.call(:AIRBALLOON, 52 + speed / 15) if damaging >= 2 && !pokemon_has_type_id?(pokemon, constant_id("PBTypes", "FLYING"))
    add_item.call(:ASSAULTVEST, 66 + special_defense / 6) if damaging >= 4 && status == 0
    add_item.call(:CHOICEBAND, 74 + physical * 4) if physical >= 3 && special == 0 && status == 0
    add_item.call(:CHOICESPECS, 74 + special * 4) if special >= 3 && physical == 0 && status == 0
    add_item.call(:CHOICESCARF, 62 + speed / 8) if damaging >= 3 && status == 0
    add_item.call(:MUSCLEBAND, 64 + physical * 5) if role == "physical" && physical >= 2
    add_item.call(:WISEGLASSES, 64 + special * 5) if role == "special" && special >= 2
    add_item.call(:LIECHIBERRY, 50 + physical * 6) if role == "physical" && physical >= 2
    add_item.call(:PETAYABERRY, 50 + special * 6) if role == "special" && special >= 2
    add_item.call(:SALACBERRY, 50 + [100 - speed, 0].max / 3) if damaging >= 2
    add_item.call(:APICOTBERRY, 46 + special_defense / 9) if special_defense >= 85
    for type, count in move_type_counts_for_item(pokemon)
      item = type_boost_item_for_type(type)
      next if item.to_i <= 0
      score = 50 + count.to_i * 12
      score += 10 if pokemon_has_type_id?(pokemon, type)
      candidates.push([item, score])
    end
    candidates.push([item_id(:LEFTOVERS), 40]) if candidates.length == 0 && item_id(:LEFTOVERS) > 0
    candidates = candidates.select { |entry| entry[0].to_i > 0 }
    return 0 if candidates.length == 0
    for entry in candidates
      entry[1] = entry[1].to_i + rand(9)
    end
    candidates.sort! { |a, b| b[1] <=> a[1] }
    best = candidates[0][1].to_i
    close = candidates.select { |entry| entry[1].to_i >= best - 22 }
    return close[rand(close.length)][0].to_i if close.length > 0
    return candidates[0][0].to_i
  rescue Exception
    return 0
  end

  def self.set_temporary_item(pokemon, item)
    return if !pokemon
    pokemon.item = item.to_i if pokemon.respond_to?(:item=)
    pokemon.itemInitial = item.to_i if pokemon.respond_to?(:itemInitial=)
  rescue Exception
  end

  def self.apply_item_rule(pokemon, rule)
    return if !pokemon || rule.to_s == "default"
    item = 0
    if rule.to_s == "random"
      pool = battle_item_pool
      item = pool[rand(pool.length)] if pool.length > 0
    elsif rule.to_s == "recommended"
      item = recommended_item(pokemon)
    end
    set_temporary_item(pokemon, item)
  rescue Exception
  end

  def self.set_temporary_form(pokemon, form)
    return if !pokemon || form == nil
    if pokemon.respond_to?(:form=)
      pokemon.form = form.to_i
    elsif pokemon.respond_to?(:formNoCall=)
      pokemon.formNoCall = form.to_i
    else
      pokemon.instance_variable_set(:@form, form.to_i)
    end
  rescue Exception
  end

  def self.clear_temporary_mega_items(party)
    ids = mega_item_ids
    for pokemon in party
      next if !pokemon
      item = pokemon.item.to_i rescue 0
      set_temporary_item(pokemon, 0) if ids[item]
    end
  rescue Exception
  end

  def self.apply_mega_rule(party, rules)
    rules = normalize_rules(rules)
    return party if rules["mega"].to_s == "default"
    clear_temporary_mega_items(party)
    candidates = []
    allow_legendary = legend_target(rules).to_i > 0
    for pokemon in party
      next if !pokemon
      next if legendary_species?(pokemon.species) && !allow_legendary
      options = mega_options_for_pokemon(pokemon)
      for option in options
        item = option["item"].to_i
        next if item <= 0
        candidates.push([pokemon, option])
      end
    end
    return party if candidates.length == 0
    choice = candidates[rand(candidates.length)]
    pokemon = choice[0]
    option = choice[1]
    set_temporary_item(pokemon, option["item"].to_i)
    set_temporary_form(pokemon, option["form"]) if option["form"] != nil
    pokemon.calcStats if pokemon.respond_to?(:calcStats)
    return party
  rescue Exception
    return party
  end

  def self.apply_custom_rules(party, rules, session = nil)
    rules = normalize_rules(rules)
    index = 0
    for pokemon in party
      next if !pokemon
      step_start = Time.now
      species_name = PBSpecies.getName(pokemon.species).to_s rescue pokemon.species.to_s
      pvp_prepare_log("prepare custom pokemon begin index=" + index.to_s + " species=" + species_name, session)
      apply_iv_rule(pokemon, rules["ivs"], rules["iv_custom"])
      apply_ev_rule(pokemon, rules["evs"], rules["ev_custom"])
      apply_move_rule(pokemon, rules["moves"])
      apply_item_rule(pokemon, rules["items"])
      pvp_prepare_log("prepare custom pokemon done index=" + index.to_s + " ms=" + elapsed_ms(step_start).to_s, session)
      index += 1
    end
    mega_start = Time.now
    apply_mega_rule(party, rules)
    pvp_prepare_log("prepare custom mega done ms=" + elapsed_ms(mega_start).to_s, session)
    for pokemon in party
      next if !pokemon
      pokemon.calcStats if pokemon.respond_to?(:calcStats)
    end
    return party
  rescue Exception
    return party
  end

  def self.prepare_party(rules, session = nil)
    rules = normalize_rules(rules)
    party = nil
    error = nil
    total_start = Time.now
    source_start = Time.now
    pvp_prepare_log("prepare source begin source=" + rules["source"].to_s, session)
    if rules["source"] == "current"
      party = current_party
      error = _INTL("No tienes Pokemon validos en el equipo.") if party.length == 0
    elsif rules["source"] == "owned"
      party, error = owned_random_party(rules)
    elsif rules["source"] == "random"
      party, error = total_random_party(rules)
    elsif rules["source"] == "teams"
      party, error = random_usage_team_party(rules)
    elsif rules["source"] == "saved"
      party, error = saved_team_party(rules)
    elsif rules["source"] == "ai"
      party, error = ai_party(rules)
    end
    pvp_prepare_log("prepare source done source=" + rules["source"].to_s + " count=" + (party ? party.length.to_s : "0") + " ms=" + elapsed_ms(source_start).to_s, session)
    return [nil, error] if error
    rule_error = validate_generated_party_rules(party, rules)
    if rule_error
      pvp_prepare_log("prepare source rule validation failed legends=" + party_legend_count(party).to_s + "/" + legend_target(rules).to_s + " error=" + rule_error.to_s, session)
      return [nil, rule_error]
    end
    party = shuffle_array(party)
    custom_start = Time.now
    apply_custom_rules(party, rules, session)
    pvp_prepare_log("prepare custom rules done ms=" + elapsed_ms(custom_start).to_s, session)
    heal_start = Time.now
    heal_party(party)
    pvp_prepare_log("prepare heal done ms=" + elapsed_ms(heal_start).to_s, session)
    pvp_prepare_log("prepare party done total_ms=" + elapsed_ms(total_start).to_s, session)
    return [party, nil]
  rescue Exception
    pvp_prepare_log("prepare party exception " + $!.class.to_s + ": " + $!.message.to_s, session)
    return [nil, _INTL("No se pudo preparar el equipo temporal del combate.")]
  end

  def self.max_level
    return PBExperience::MAXLEVEL if defined?(PBExperience) && PBExperience.const_defined?(:MAXLEVEL)
    return MAXIMUMLEVEL if Object.const_defined?(:MAXIMUMLEVEL)
    return 100
  rescue Exception
    return 100
  end

  def self.normalize_party_level(party, level)
    level = level.to_i
    level = 1 if level < 1
    level = max_level if level > max_level
    for pokemon in party
      next if !pokemon
      pokemon.level = level if pokemon.respond_to?(:level=)
      pokemon.calcStats if pokemon.respond_to?(:calcStats)
      pokemon.heal if pokemon.respond_to?(:heal)
    end
    return party
  rescue Exception
    return party
  end

  def self.apply_level_rule(local_party, remote_party, rules, local_source_level, remote_source_level)
    rules = normalize_rules(rules)
    level = nil
    level = 50 if rules["level"] == "50"
    level = 100 if rules["level"] == "100"
    if rules["level"] == "highest"
      level = [local_source_level.to_i, remote_source_level.to_i].max
      level = 1 if level <= 0
    end
    if level
      normalize_party_level(local_party, level)
      normalize_party_level(remote_party, level)
    end
    return level
  rescue Exception
    return nil
  end

  def self.party_preview_text(party)
    lines = []
    for pokemon in shuffle_array(party)
      next if !pokemon
      species = PBSpecies.getName(pokemon.species).to_s rescue pokemon.name.to_s
      lines.push("- " + species + " Nv." + pokemon.level.to_i.to_s)
    end
    return lines.join("\n")
  rescue Exception
    return ""
  end

  def self.choose_lead_indexes(party, count)
    scene = PokemonScreen_Scene.new
    screen = PokemonScreen.new(scene, party)
    selected = []
    begin
      screen.pbStartScene(_INTL("Elige el Pokemon inicial. El rival no vera tu eleccion."), false)
      while selected.length < count
        message = selected.length == 0 ? _INTL("Elige tu primer Pokemon.") : _INTL("Elige tu segundo Pokemon.")
        index = screen.pbChoosePokemon(message)
        if index == nil || index < 0 || index >= party.length
          screen.pbEndScene
          return nil
        end
        if selected.include?(index)
          Kernel.pbMessage(_INTL("Ese Pokemon ya esta elegido como inicial."))
          next
        end
        selected.push(index)
      end
      screen.pbEndScene
      return selected
    rescue Exception
      begin
        screen.pbEndScene
      rescue Exception
      end
      return nil
    end
  end

  def self.reorder_party(party, indexes)
    ret = []
    used = {}
    for index in indexes
      index = index.to_i
      next if index < 0 || index >= party.length || used[index]
      ret.push(party[index])
      used[index] = true
    end
    for i in 0...party.length
      ret.push(party[i]) if !used[i]
    end
    return ret
  rescue Exception
    return party
  end

  def self.valid_lead_indexes?(party, indexes, count)
    return false if !party || !indexes || indexes.length < count.to_i
    seen = {}
    for i in 0...count.to_i
      index = indexes[i].to_i
      return false if index < 0 || index >= party.length
      return false if seen[index]
      seen[index] = true
    end
    return true
  rescue Exception
    return false
  end
end

module SebiPvpPreview
  CONFIRM_INDEX = 12

  def self.runtime_dir
    return SebiLinkPaths.runtime_dir("pvp-preview") if defined?(SebiLinkPaths)
    return File.expand_path("multiplayer/pvp-preview/runtime")
  rescue Exception
    return "multiplayer/pvp-preview/runtime"
  end

  def self.window_path
    return File.expand_path("multiplayer/pvp-preview/SebiPvpPreview.ps1")
  rescue Exception
    return "multiplayer/pvp-preview/SebiPvpPreview.ps1"
  end

  def self.ensure_runtime
    SebiLinkPaths.ensure_dir(runtime_dir) if defined?(SebiLinkPaths)
  rescue Exception
  end

  def self.safe_token(token)
    return token.to_s.gsub(/[^A-Za-z0-9_-]/, "_")
  rescue Exception
    return "battle"
  end

  def self.state_path(token)
    return File.join(runtime_dir, "state_" + safe_token(token) + ".json")
  end

  def self.result_path(token)
    return File.join(runtime_dir, "result_" + safe_token(token) + ".txt")
  end

  def self.type_chart_for(pokemon)
    chart = {
      "x0" => [],
      "x025" => [],
      "x05" => [],
      "x1" => [],
      "x2" => [],
      "x4" => []
    }
    return chart if !pokemon || !defined?(PBTypes)
    type1 = pokemon.type1.to_i rescue -1
    type2 = pokemon.type2.to_i rescue type1
    for type in 0..PBTypes.maxValue
      next if PBTypes.isPseudoType?(type) rescue false
      name = PBTypes.getName(type).to_s rescue type.to_s
      mod = PBTypes.getCombinedEffectiveness(type, type1, type2, -1) rescue 8
      key = "x1"
      key = "x0" if mod == 0
      key = "x025" if mod > 0 && mod <= 2
      key = "x05" if mod > 2 && mod < 8
      key = "x2" if mod > 8 && mod < 32
      key = "x4" if mod >= 32
      chart[key].push(name)
    end
    return chart
  rescue Exception
    return chart || {}
  end

  def self.rival_pokemon_data(pokemon, index)
    return nil if !pokemon
    species = pokemon.species.to_i rescue 0
    type1 = pokemon.type1.to_i rescue -1
    type2 = pokemon.type2.to_i rescue type1
    return {
      "index" => index,
      "species" => species,
      "speciesName" => (PBSpecies.getName(species).to_s rescue pokemon.name.to_s),
      "level" => (pokemon.level.to_i rescue 1),
      "type1" => type1,
      "type1Name" => (PBTypes.getName(type1).to_s rescue ""),
      "type2" => type2,
      "type2Name" => (PBTypes.getName(type2).to_s rescue ""),
      "baseStats" => (defined?(SebiBattleAdvisor) ? SebiBattleAdvisor.base_stats_for_pokemon(pokemon) : [0, 0, 0, 0, 0, 0]),
      "typeChart" => type_chart_for(pokemon)
    }
  rescue Exception
    return nil
  end

  def self.own_party_data(party)
    return SebiBattleAdvisor.party_data(party, "pvpPreviewOwn") if defined?(SebiBattleAdvisor)
    return []
  rescue Exception
    return []
  end

  def self.rival_party_data(party)
    ret = []
    return ret if !party
    for i in 0...party.length
      data = rival_pokemon_data(party[i], i)
      ret.push(data) if data
    end
    return ret
  rescue Exception
    return []
  end

  def self.write_state(session, local_party, remote_party)
    return false if !defined?(SebiBattleAdvisor)
    ensure_runtime
    state = {
      "generatedAt" => Time.now.to_s,
      "token" => session[:token].to_s,
      "playerName" => SebiVisualMultiplayer.local_name,
      "rivalName" => session[:remote_name].to_s,
      "mode" => session[:mode].to_s,
      "rules" => (defined?(SebiPvpRules) ? SebiPvpRules.summary(session[:rules]) : ""),
      "ownParty" => own_party_data(local_party),
      "rivalParty" => rival_party_data(remote_party)
    }
    SebiBattleAdvisor.atomic_write(state_path(session[:token]), SebiBattleAdvisor.json(state))
    return true
  rescue Exception
    return false
  end

  def self.quote_arg(value)
    return "\"" + value.to_s.gsub("\"", "") + "\""
  rescue Exception
    return "\"\""
  end

  def self.open_window(session)
    return false if !defined?(SebiBattleAdvisor)
    path = window_path
    return false if !FileTest.exist?(path)
    params = "-StatePath " + quote_arg(state_path(session[:token])) +
             " -ResultPath " + quote_arg(result_path(session[:token]))
    return SebiBattleAdvisor.open_powershell_script(path, params)
  rescue Exception
    return false
  end

  def self.read_result(path)
    return nil if !FileTest.exist?(path)
    value = ""
    File.open(path, "rb") { |file| value = file.read.to_s.strip }
    return value
  rescue Exception
    return nil
  end

  def self.pokemon_name(pokemon)
    return _INTL("Pokemon") if !pokemon
    species = pokemon.species.to_i rescue 0
    name = PBSpecies.getName(species).to_s rescue ""
    name = pokemon.name.to_s if name == ""
    return name == "" ? _INTL("Pokemon") : name
  rescue Exception
    return _INTL("Pokemon")
  end

  def self.type_names(pokemon)
    return [] if !pokemon
    type1 = pokemon.type1.to_i rescue -1
    type2 = pokemon.type2.to_i rescue type1
    ret = []
    ret.push(PBTypes.getName(type1).to_s) if defined?(PBTypes) && type1 >= 0
    ret.push(PBTypes.getName(type2).to_s) if defined?(PBTypes) && type2 >= 0 && type2 != type1
    return ret
  rescue Exception
    return []
  end

  def self.type_ids(pokemon)
    return [] if !pokemon
    type1 = pokemon.type1.to_i rescue -1
    type2 = pokemon.type2.to_i rescue type1
    ret = []
    ret.push(type1) if type1 >= 0
    ret.push(type2) if type2 >= 0 && type2 != type1
    return ret
  rescue Exception
    return []
  end

  def self.type_chart_ids_for(pokemon)
    chart = {
      "x0" => [],
      "x025" => [],
      "x05" => [],
      "x1" => [],
      "x2" => [],
      "x4" => []
    }
    return chart if !pokemon || !defined?(PBTypes)
    type1 = pokemon.type1.to_i rescue -1
    type2 = pokemon.type2.to_i rescue type1
    for type in 0..PBTypes.maxValue
      next if PBTypes.isPseudoType?(type) rescue false
      mod = PBTypes.getCombinedEffectiveness(type, type1, type2, -1) rescue 8
      key = "x1"
      key = "x0" if mod == 0
      key = "x025" if mod > 0 && mod <= 2
      key = "x05" if mod > 2 && mod < 8
      key = "x2" if mod > 8 && mod < 32
      key = "x4" if mod >= 32
      chart[key].push(type)
    end
    return chart
  rescue Exception
    return chart || {}
  end

  def self.type_icon_bitmap
    @type_icon_bitmap = AnimatedBitmap.new(_INTL("Graphics/Pictures/types")) if !@type_icon_bitmap
    return @type_icon_bitmap.bitmap
  rescue Exception
    return nil
  end

  def self.type_ico_bitmap
    @type_ico_bitmap = AnimatedBitmap.new(_INTL("Graphics/Pictures/types_ico")) if !@type_ico_bitmap
    return @type_ico_bitmap.bitmap
  rescue Exception
    return nil
  end

  def self.category_icon_bitmap
    @category_icon_bitmap = AnimatedBitmap.new(_INTL("Graphics/Pictures/category")) if !@category_icon_bitmap
    return @category_icon_bitmap.bitmap
  rescue Exception
    return nil
  end

  def self.draw_sheet_icon(bitmap, sheet, index, x, y, width, height)
    draw_sheet_icon_from(bitmap, sheet, index, x, y, width, height, 64, 28)
  rescue Exception
  end

  def self.draw_sheet_icon_from(bitmap, sheet, index, x, y, width, height, source_width, source_height)
    return if !bitmap || !sheet || index.to_i < 0
    source_width = source_width.to_i
    source_height = source_height.to_i
    return if source_width <= 0 || source_height <= 0
    source_y = index.to_i * source_height
    return if sheet.respond_to?(:height) && source_y >= sheet.height.to_i
    if sheet.respond_to?(:height) && source_y + source_height > sheet.height.to_i
      source_height = sheet.height.to_i - source_y
    end
    if sheet.respond_to?(:width) && source_width > sheet.width.to_i
      source_width = sheet.width.to_i
    end
    source = Rect.new(0, source_y, source_width, source_height)
    target = Rect.new(x.to_i, y.to_i, width.to_i, height.to_i)
    bitmap.stretch_blt(target, sheet, source)
  rescue Exception
  end

  def self.draw_type_ico(bitmap, index, x, y, width = 15, height = 17)
    draw_sheet_icon_from(bitmap, type_ico_bitmap, index, x, y, width, height, 24, 28)
  rescue Exception
  end

  def self.draw_type_icons(bitmap, pokemon, x, y, width = 42, height = 18)
    ids = type_ids(pokemon)
    for i in 0...ids.length
      draw_sheet_icon(bitmap, type_icon_bitmap, ids[i], x + i * (width + 4), y, width, height)
    end
  rescue Exception
  end

  def self.draw_type_icons_compact(bitmap, pokemon, x, y, width = 15, height = 17)
    ids = type_ids(pokemon)
    for i in 0...ids.length
      draw_type_ico(bitmap, ids[i], x + i * (width + 3), y, width, height)
    end
  rescue Exception
  end

  def self.draw_type_icon_row(bitmap, label, ids, x, y)
    draw_text(bitmap, label, x, y, 0)
    ids = ids || []
    start_x = x + 58
    max_icons = 9
    count = [ids.length, max_icons].min
    for i in 0...count
      draw_type_ico(bitmap, ids[i], start_x + i * 18, y, 16, 18)
    end
    if ids.length > max_icons
      draw_text(bitmap, "+" + (ids.length - max_icons).to_s, start_x + max_icons * 18, y, 0)
    end
  rescue Exception
  end

  def self.fit_text(bitmap, text, max_width)
    value = text.to_s
    return value if !bitmap || bitmap.text_size(value).width <= max_width.to_i
    suffix = "..."
    while value.length > 1 && bitmap.text_size(value + suffix).width > max_width.to_i
      value = value[0, value.length - 1]
    end
    return value + suffix
  rescue Exception
    return text.to_s
  end

  def self.move_data(move)
    return nil if !move || (move.id.to_i rescue 0) <= 0
    return PBMoveData.new(move.id)
  rescue Exception
    return nil
  end

  def self.move_power_text(move)
    data = move_data(move)
    return "---" if !data || data.basedamage.to_i <= 0
    return "???" if data.basedamage.to_i == 1
    return data.basedamage.to_i.to_s
  rescue Exception
    return "---"
  end

  def self.move_accuracy_text(move)
    data = move_data(move)
    return "---" if !data || data.accuracy.to_i <= 0
    return data.accuracy.to_i.to_s
  rescue Exception
    return "---"
  end

  def self.move_description(move)
    return "" if !move || (move.id.to_i rescue 0) <= 0
    return pbGetMessage(MessageTypes::MoveDescriptions, move.id.to_i).to_s if defined?(MessageTypes)
    return ""
  rescue Exception
    return ""
  end

  def self.csv_fields(line)
    fields = []
    current = ""
    quoted = false
    i = 0
    text = line.to_s.strip
    while i < text.length
      char = text[i, 1]
      if char == "\""
        if quoted && text[i + 1, 1] == "\""
          current += "\""
          i += 1
        else
          quoted = !quoted
        end
      elsif char == "," && !quoted
        fields.push(current)
        current = ""
      else
        current += char
      end
      i += 1
    end
    fields.push(current)
    return fields
  rescue Exception
    return []
  end

  def self.ability_descriptions
    return @ability_descriptions if @ability_descriptions
    @ability_descriptions = {}
    path = "PBS/abilities.txt"
    if FileTest.exist?(path)
      File.open(path, "rb") do |file|
        file.each_line do |line|
          next if line.to_s.strip == "" || line.to_s.strip[0, 1] == "#"
          fields = csv_fields(line)
          begin
            id = fields[0].to_i
          rescue Exception
            id = 0
          end
          @ability_descriptions[id] = fields[3].to_s if id > 0 && fields.length >= 4
        end
      end
    end
    return @ability_descriptions
  rescue Exception
    @ability_descriptions = {}
    return @ability_descriptions
  end

  def self.ability_id(pokemon)
    return pokemon.ability.to_i rescue 0
  end

  def self.ability_name(pokemon)
    id = ability_id(pokemon)
    return PBAbilities.getName(id).to_s if id > 0 && defined?(PBAbilities)
    return "-"
  rescue Exception
    return "-"
  end

  def self.ability_description(id)
    value = ability_descriptions[id.to_i]
    return value.to_s if value && value.to_s != ""
    return _INTL("No hay descripcion disponible para esta habilidad.")
  rescue Exception
    return ""
  end

  def self.item_id(pokemon)
    return pokemon.item.to_i rescue 0
  end

  def self.item_name(pokemon)
    id = item_id(pokemon)
    return "-" if id <= 0
    return PBItems.getName(id).to_s if defined?(PBItems)
    return id.to_s
  rescue Exception
    return "-"
  end

  def self.item_description(id)
    id = id.to_i
    return _INTL("No lleva objeto equipado.") if id <= 0
    return pbGetMessage(MessageTypes::ItemDescriptions, id).to_s if defined?(MessageTypes)
    return ""
  rescue Exception
    return ""
  end

  def self.detail_entry_count(pokemon)
    count = 3
    moves = pokemon.moves rescue []
    for i in 0...4
      move = moves[i] rescue nil
      count += 1 if move && (move.id.to_i rescue 0) > 0
    end
    return count
  rescue Exception
    return 3
  end

  def self.detail_entry(pokemon, cursor)
    cursor = cursor.to_i
    if cursor <= 0
      return {
        :title => _INTL("Tipos y efectividades"),
        :subtitle => "",
        :description => "",
        :kind => :type_chart,
        :chart => type_chart_ids_for(pokemon)
      }
    elsif cursor == 1
      id = ability_id(pokemon)
      name = ability_name(pokemon)
      return {
        :title => _INTL("Habilidad: {1}", name),
        :subtitle => "",
        :description => ability_description(id)
      }
    elsif cursor == 2
      id = item_id(pokemon)
      name = item_name(pokemon)
      return {
        :title => _INTL("Objeto: {1}", name),
        :subtitle => "",
        :description => item_description(id)
      }
    end
    move_index = cursor - 3
    move = pokemon.moves[move_index] rescue nil
    if !move || (move.id.to_i rescue 0) <= 0
      return { :title => _INTL("Movimiento"), :subtitle => "", :description => "" }
    end
    data = move_data(move)
    category = data ? data.category.to_i : -1
    category_name = SebiMoveInfo.category_name(category) if defined?(SebiMoveInfo)
    category_name = category.to_s if !category_name
    move_name = PBMoves.getName(move.id).to_s rescue move.name.to_s
    pp = move.totalpp.to_i > 0 ? _INTL("{1}/{2}", move.pp.to_i, move.totalpp.to_i) : "---"
    return {
      :title => move_name,
      :subtitle => _INTL("PP {1}  Pot. {2}  Prec. {3}  {4}", pp, move_power_text(move), move_accuracy_text(move), category_name),
      :description => move_description(move)
    }
  rescue Exception
    return { :title => "", :subtitle => "", :description => "" }
  end

  def self.wrap_text_lines(bitmap, text, max_width, max_lines)
    words = text.to_s.gsub(/\r\n?/, " ").split(/\s+/)
    lines = []
    current = ""
    for word in words
      candidate = current == "" ? word : current + " " + word
      if bitmap && bitmap.text_size(candidate).width > max_width.to_i && current != ""
        lines.push(current)
        current = word
        break if lines.length >= max_lines.to_i
      else
        current = candidate
      end
    end
    lines.push(current) if current != "" && lines.length < max_lines.to_i
    if words.length > 0 && lines.length == max_lines.to_i
      last = lines[lines.length - 1]
      while bitmap && bitmap.text_size(last + "...").width > max_width.to_i && last.length > 1
        last = last[0, last.length - 1]
      end
      lines[lines.length - 1] = last + "..." if last != lines[lines.length - 1]
    end
    return lines
  rescue Exception
    return [text.to_s]
  end

  def self.draw_wrapped_text(bitmap, text, x, y, max_width, max_lines, base = nil, shadow = nil)
    lines = wrap_text_lines(bitmap, text, max_width, max_lines)
    for i in 0...lines.length
      draw_text(bitmap, lines[i], x, y + i * 16, 0, base, shadow)
    end
  rescue Exception
  end

  def self.ordered_stat_array(source)
    values = source || []
    return [
      (values[0].to_i rescue 0),
      (values[1].to_i rescue 0),
      (values[2].to_i rescue 0),
      (values[4].to_i rescue 0),
      (values[5].to_i rescue 0),
      (values[3].to_i rescue 0)
    ]
  rescue Exception
    return [0, 0, 0, 0, 0, 0]
  end

  def self.base_stats(pokemon)
    return SebiBattleAdvisor.base_stats_for_pokemon(pokemon) if defined?(SebiBattleAdvisor)
    return [0, 0, 0, 0, 0, 0]
  rescue Exception
    return [0, 0, 0, 0, 0, 0]
  end

  def self.real_stats(pokemon)
    return [
      (pokemon.totalhp.to_i rescue 0),
      (pokemon.attack.to_i rescue 0),
      (pokemon.defense.to_i rescue 0),
      (pokemon.spatk.to_i rescue 0),
      (pokemon.spdef.to_i rescue 0),
      (pokemon.speed.to_i rescue 0)
    ]
  rescue Exception
    return [0, 0, 0, 0, 0, 0]
  end

  def self.stat_color(value)
    value = value.to_i
    return Color.new(126, 214, 126) if value >= 120
    return Color.new(173, 226, 137) if value >= 100
    return Color.new(255, 232, 132) if value >= 80
    return Color.new(255, 201, 118) if value >= 60
    return Color.new(255, 153, 132)
  rescue Exception
    return Color.new(220, 220, 220)
  end

  def self.draw_box(bitmap, x, y, width, height, fill, edge)
    bitmap.fill_rect(x, y, width, height, edge)
    bitmap.fill_rect(x + 2, y + 2, width - 4, height - 4, fill)
  rescue Exception
  end

  def self.draw_text(bitmap, text, x, y, align = 0, base = nil, shadow = nil)
    base = Color.new(40, 40, 48) if !base
    value = text.to_s
    apply_preview_font(bitmap)
    shadow = transparent_shadow(base)
    pbDrawTextPositions(bitmap, [[value, x, y, align, base, shadow]])
  rescue Exception
    begin
      old_color = bitmap.font.color rescue nil
      bitmap.font.color = base if bitmap.respond_to?(:font) && bitmap.font && bitmap.font.respond_to?(:color=)
      width = bitmap.text_size(value).width + 8 rescue 160
      width = 8 if width < 8
      rect_x = x.to_i
      draw_align = 0
      if align.to_i == 2
        rect_x = x.to_i - width / 2
        draw_align = 1
      elsif align.to_i == 1
        rect_x = x.to_i - width
        draw_align = 2
      end
      bitmap.draw_text(Rect.new(rect_x, y.to_i, width, 24), value, draw_align)
      bitmap.font.color = old_color if old_color && bitmap.respond_to?(:font) && bitmap.font && bitmap.font.respond_to?(:color=)
    rescue Exception
    end
  end

  def self.transparent_shadow(base)
    return Color.new(base.red, base.green, base.blue, 0)
  rescue Exception
    return Color.new(0, 0, 0, 0)
  end

  def self.apply_preview_font(bitmap)
    return if !bitmap || !bitmap.respond_to?(:font) || !bitmap.font
    bitmap.font.name = "Power Green Small" if bitmap.font.respond_to?(:name=)
    bitmap.font.bold = false if bitmap.font.respond_to?(:bold=)
  end

  def self.half_width
    return Graphics.width / 2
  rescue Exception
    return 256
  end

  def self.team_half(index)
    return index.to_i >= 6 ? 1 : 0
  end

  def self.panel_rect(index)
    group = team_half(index)
    slot = index.to_i % 6
    x = group == 0 ? 4 : half_width + 4
    y = 28 + slot * 47
    return [x, y, half_width - 8, 42]
  rescue Exception
    return [0, 0, 248, 42]
  end

  def self.cell_position(index)
    x, y, width, height = panel_rect(index)
    return [x, y]
  end

  def self.valid_indexes(local_party, remote_party)
    ret = []
    for i in 0...local_party.length
      ret.push(i) if local_party[i]
    end
    for i in 0...remote_party.length
      ret.push(6 + i) if remote_party[i]
    end
    return ret
  rescue Exception
    return []
  end

  def self.confirm_index
    return CONFIRM_INDEX
  end

  def self.index_valid?(index, local_party, remote_party)
    index = index.to_i
    if index < 6
      return local_party[index] != nil rescue false
    end
    return remote_party[index - 6] != nil rescue false
  rescue Exception
    return false
  end

  def self.indexes_for_half(group, local_party, remote_party)
    ret = []
    start_index = group.to_i == 0 ? 0 : 6
    party = group.to_i == 0 ? local_party : remote_party
    for i in 0...6
      begin
        ret.push(start_index + i) if party[i]
      rescue Exception
      end
    end
    return ret
  rescue Exception
    return []
  end

  def self.next_index(current, direction, local_party, remote_party)
    indexes = valid_indexes(local_party, remote_party)
    return current if indexes.length == 0
    current = indexes[0] if current.to_i == confirm_index
    current = indexes[0] if !indexes.include?(current)
    group = team_half(current)
    slot = current.to_i % 6
    if direction == :previous || direction == :next
      target = group == 0 ? 6 + slot : slot
      return target if index_valid?(target, local_party, remote_party)
      pos = indexes.index(current) || 0
      return indexes[(pos + (direction == :previous ? -1 : 1)) % indexes.length]
    end
    half_indexes = indexes_for_half(group, local_party, remote_party)
    return current if half_indexes.length == 0
    pos = half_indexes.index(current) || 0
    step = direction == :up ? -1 : 1
    return half_indexes[(pos + step) % half_indexes.length]
  rescue Exception
    return current
  end

  def self.next_index_for_preview(current, direction, local_party, remote_party)
    indexes = valid_indexes(local_party, remote_party)
    return current if indexes.length == 0
    if current.to_i == confirm_index
      return indexes[0] if direction == :up
      return current
    end
    if direction == :down
      half_indexes = indexes_for_half(team_half(current), local_party, remote_party)
      pos = half_indexes.index(current) || 0
      return confirm_index if pos >= half_indexes.length - 1
    end
    return next_index(current, direction, local_party, remote_party)
  rescue Exception
    return current
  end

  def self.create_icons(local_party, remote_party, viewport)
    icons = {}
    parties = [local_party, remote_party]
    for group in 0...parties.length
      party = parties[group]
      for i in 0...party.length
        next if !party[i]
        index = group == 0 ? i : 6 + i
        x, y, width, height = panel_rect(index)
        sprite = PokemonIconSprite.new(party[i], viewport)
        sprite.zoom_x = 0.62 if sprite.respond_to?(:zoom_x=)
        sprite.zoom_y = 0.62 if sprite.respond_to?(:zoom_y=)
        sprite.x = x + 22
        sprite.y = y - 2
        sprite.z = 3
        icons[index] = sprite
      end
    end
    return icons
  rescue Exception
    return icons || {}
  end

  def self.detail_indexes_array(detail_indexes)
    ret = [nil, nil]
    if detail_indexes.is_a?(Array)
      ret[0] = detail_indexes[0]
      ret[1] = detail_indexes[1]
    elsif detail_indexes != nil
      ret[team_half(detail_indexes)] = detail_indexes
    end
    return ret
  rescue Exception
    return [nil, nil]
  end

  def self.any_detail_open?(detail_indexes)
    values = detail_indexes_array(detail_indexes)
    return values[0] != nil || values[1] != nil
  rescue Exception
    return false
  end

  def self.detail_for_selected(selected, detail_indexes)
    return nil if selected == nil || selected.to_i == confirm_index
    values = detail_indexes_array(detail_indexes)
    return values[team_half(selected)]
  rescue Exception
    return nil
  end

  def self.update_icons(icons, selected, detail_indexes = nil)
    values = detail_indexes_array(detail_indexes)
    for index in icons.keys
      sprite = icons[index]
      next if !sprite
      sprite.visible = values[team_half(index)] == nil if sprite.respond_to?(:visible=)
      sprite.selected = index.to_i == selected.to_i if sprite.respond_to?(:selected=)
      sprite.update if sprite.respond_to?(:update)
    end
  rescue Exception
  end

  def self.draw_team_cells(bitmap, party, start_index, selected)
    for i in 0...6
      index = start_index + i
      pokemon = party[i] rescue nil
      draw_party_panel(bitmap, pokemon, index, index.to_i == selected.to_i)
    end
  rescue Exception
  end

  def self.party_bg_bitmap
    @party_bg_bitmap = AnimatedBitmap.new("Graphics/Pictures/partybg") if !@party_bg_bitmap
    return @party_bg_bitmap.bitmap
  rescue Exception
    return nil
  end

  def self.party_ball_bitmap(selected = false)
    key = selected ? :selected : :normal
    @party_ball_bitmaps = {} if !@party_ball_bitmaps
    if !@party_ball_bitmaps[key]
      path = selected ? "Graphics/Pictures/partyBallSel" : "Graphics/Pictures/partyBall"
      @party_ball_bitmaps[key] = AnimatedBitmap.new(path)
    end
    return @party_ball_bitmaps[key].bitmap
  rescue Exception
    return nil
  end

  def self.draw_party_background(bitmap)
    bg = party_bg_bitmap
    if bg
      bitmap.stretch_blt(Rect.new(0, 0, Graphics.width, Graphics.height), bg, Rect.new(0, 0, bg.width, bg.height))
    else
      bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(32, 68, 112))
      for x in 0..Graphics.width
        bitmap.fill_rect(x, 0, 1, Graphics.height, Color.new(44, 84, 132)) if x % 16 == 0
      end
      for y in 0..Graphics.height
        bitmap.fill_rect(0, y, Graphics.width, 1, Color.new(44, 84, 132)) if y % 16 == 0
      end
    end
    bitmap.fill_rect(0, 0, Graphics.width, 24, Color.new(28, 52, 88))
    bitmap.fill_rect(half_width - 1, 24, 2, 292, Color.new(22, 45, 72))
  rescue Exception
  end

  def self.gender_label(pokemon)
    return ["♂", Color.new(72, 168, 248), Color.new(24, 64, 120)] if pokemon && pokemon.isMale?
    return ["♀", Color.new(248, 96, 136), Color.new(120, 24, 48)] if pokemon && pokemon.isFemale?
    return ["", Color.new(248, 248, 248), Color.new(40, 40, 40)]
  rescue Exception
    return ["", Color.new(248, 248, 248), Color.new(40, 40, 40)]
  end

  def self.hp_values(pokemon)
    hp = pokemon.hp.to_i rescue 0
    total = pokemon.totalhp.to_i rescue 0
    total = 1 if total <= 0
    hp = total if hp > total
    hp = 0 if hp < 0
    return [hp, total]
  rescue Exception
    return [0, 1]
  end

  def self.hp_color(hp, total)
    return Color.new(248, 72, 56) if hp <= (total / 4).floor
    return Color.new(248, 216, 0) if hp <= (total / 2).floor
    return Color.new(96, 248, 96)
  rescue Exception
    return Color.new(96, 248, 96)
  end

  def self.draw_hp_bar(bitmap, pokemon, x, y, width = 96)
    hp, total = hp_values(pokemon)
    gauge = hp * width / total
    gauge = 1 if gauge == 0 && hp > 0
    bitmap.fill_rect(x, y, width + 2, 8, Color.new(24, 32, 28))
    bitmap.fill_rect(x + 1, y + 1, width, 6, Color.new(232, 240, 232))
    bitmap.fill_rect(x + 1, y + 1, gauge, 6, hp_color(hp, total))
  rescue Exception
  end

  def self.draw_party_panel(bitmap, pokemon, index, selected)
    x, y, width, height = panel_rect(index)
    edge = selected ? Color.new(248, 232, 56) : Color.new(40, 196, 64)
    fill = pokemon ? Color.new(0, 146, 56) : Color.new(28, 96, 68)
    shadow = Color.new(8, 78, 40)
    bitmap.fill_rect(x, y, width, height, Color.new(30, 52, 40))
    bitmap.fill_rect(x + 2, y + 2, width - 4, height - 4, edge)
    bitmap.fill_rect(x + 5, y + 5, width - 10, height - 10, fill)
    bitmap.fill_rect(x + 5, y + height - 10, width - 10, 5, shadow)
    ball = party_ball_bitmap(selected)
    bitmap.blt(x + 5, y + 2, ball, Rect.new(0, 0, ball.width, ball.height)) if ball
    if !pokemon
      draw_text(bitmap, _INTL("Vacio"), x + width / 2, y + 10, 2, Color.new(248, 248, 248), Color.new(40, 40, 40))
      return
    end
    base = Color.new(248, 248, 248)
    text_shadow = Color.new(32, 48, 40)
    name = fit_text(bitmap, pokemon_name(pokemon), width - 112)
    draw_text(bitmap, name, x + 88, y + 2, 0, base, text_shadow)
    gender, gender_base, gender_shadow = gender_label(pokemon)
    draw_text(bitmap, gender, x + width - 18, y + 2, 0, gender_base, gender_shadow) if gender != ""
    draw_text(bitmap, _INTL("Nv.{1}", (pokemon.level.to_i rescue 1)), x + 10, y + 25, 0, base, text_shadow)
    draw_hp_bar(bitmap, pokemon, x + 88, y + 23, width - 126)
    hp, total = hp_values(pokemon)
    draw_text(bitmap, _INTL("{1}/{2}", hp, total), x + width - 8, y + 25, 1, base, text_shadow)
  rescue Exception
  end

  def self.draw_stat_table(bitmap, pokemon, include_real)
    names = [_INTL("PS"), _INTL("Atq"), _INTL("Def"), _INTL("AtqEsp"), _INTL("DefEsp"), _INTL("Vel")]
    base = base_stats(pokemon)
    raw_ivs = pokemon.iv rescue []
    raw_evs = pokemon.ev rescue []
    ivs = ordered_stat_array(raw_ivs)
    evs = ordered_stat_array(raw_evs)
    stats = real_stats(pokemon)
    base_x = 88
    iv_x = 132
    ev_x = 174
    stats_x = 218
    draw_text(bitmap, _INTL("Base"), base_x, 234, 2)
    draw_text(bitmap, _INTL("IVs"), iv_x, 234, 2)
    draw_text(bitmap, _INTL("EVs"), ev_x, 234, 2)
    draw_text(bitmap, _INTL("Stats"), stats_x, 234, 2)
    for i in 0...6
      y = 251 + i * 16
      draw_text(bitmap, names[i], 18, y, 0)
      bitmap.fill_rect(base_x - 18, y + 1, 36, 15, stat_color(base[i]))
      draw_text(bitmap, base[i].to_i.to_s, base_x, y, 2, Color.new(30, 30, 30), Color.new(255, 255, 255))
      if include_real
        draw_text(bitmap, ivs[i].to_i.to_s, iv_x, y, 2)
        draw_text(bitmap, evs[i].to_i.to_s, ev_x, y, 2)
        draw_text(bitmap, stats[i].to_i.to_s, stats_x, y, 2)
      else
        draw_text(bitmap, "?", iv_x, y, 2)
        draw_text(bitmap, "?", ev_x, y, 2)
        draw_text(bitmap, "?", stats_x, y, 2)
      end
    end
  rescue Exception
  end

  def self.draw_own_details(bitmap, pokemon)
    draw_stat_table(bitmap, pokemon, true)
    ability = PBAbilities.getName(pokemon.ability).to_s rescue "-"
    item = pokemon.item.to_i > 0 ? (PBItems.getName(pokemon.item).to_s rescue "-") : "-"
    draw_text(bitmap, _INTL("{1} Nv.{2}", pokemon_name(pokemon), (pokemon.level.to_i rescue 1)), 250, 229, 0)
    draw_text(bitmap, _INTL("Tipos:"), 250, 247, 0)
    draw_type_icons_compact(bitmap, pokemon, 296, 248, 17, 19)
    draw_text(bitmap, fit_text(bitmap, _INTL("Habilidad: {1}", ability), 246), 250, 267, 0)
    draw_text(bitmap, fit_text(bitmap, _INTL("Objeto: {1}", item), 246), 250, 284, 0)
    draw_text(bitmap, _INTL("Movimientos:"), 250, 301, 0)
    old_size = bitmap.font.size rescue nil
    bitmap.font.size = 11 if bitmap.respond_to?(:font) && bitmap.font
    moves = pokemon.moves rescue []
    for i in 0...4
      move = moves[i] rescue nil
      next if !move || (move.id.to_i rescue 0) <= 0
      x = 250 + (i % 2) * 126
      y = 316 + (i / 2) * 21
      bitmap.fill_rect(x, y, 122, 20, Color.new(226, 231, 235))
      bitmap.fill_rect(x + 1, y + 1, 120, 18, Color.new(248, 249, 250))
      data = move_data(move)
      draw_sheet_icon(bitmap, type_icon_bitmap, (move.type.to_i rescue (data ? data.type.to_i : -1)), x + 2, y + 2, 22, 10)
      draw_sheet_icon(bitmap, category_icon_bitmap, (data ? data.category.to_i : -1), x + 27, y + 2, 22, 10)
      move_name = PBMoves.getName(move.id).to_s rescue move.name.to_s
      draw_text(bitmap, fit_text(bitmap, move_name, 70), x + 51, y, 0)
      pp = move.totalpp.to_i > 0 ? _INTL("{1}/{2}", move.pp.to_i, move.totalpp.to_i) : "---"
      draw_text(bitmap, _INTL("PP {1}", pp), x + 4, y + 9, 0)
      draw_text(bitmap, _INTL("Pot. {1}", move_power_text(move)), x + 64, y + 9, 0)
    end
    bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
  rescue Exception
  end

  def self.draw_rival_details(bitmap, pokemon)
    draw_stat_table(bitmap, pokemon, false)
    chart = type_chart_ids_for(pokemon)
    draw_text(bitmap, _INTL("{1} Nv.{2}", pokemon_name(pokemon), (pokemon.level.to_i rescue 1)), 250, 229, 0)
    draw_text(bitmap, _INTL("Tipos:"), 250, 247, 0)
    draw_type_icons_compact(bitmap, pokemon, 296, 248, 17, 19)
    draw_type_icon_row(bitmap, _INTL("Debil x4:"), chart["x4"], 250, 270)
    draw_type_icon_row(bitmap, _INTL("Debil x2:"), chart["x2"], 250, 288)
    draw_type_icon_row(bitmap, _INTL("Resiste:"), chart["x05"], 250, 306)
    draw_type_icon_row(bitmap, _INTL("Inmune:"), chart["x0"], 250, 324)
    old_size = bitmap.font.size rescue nil
    bitmap.font.size = 12 if bitmap.respond_to?(:font) && bitmap.font
    draw_text(bitmap, _INTL("IVs, EVs, stats reales, movimientos, habilidad y objeto ocultos."), 250, 344, 0)
    bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
  rescue Exception
  end

  def self.draw_stat_table_at(bitmap, pokemon, include_real, x, y, width)
    names = [_INTL("PS"), _INTL("Atq"), _INTL("Def"), _INTL("AtqEsp"), _INTL("DefEsp"), _INTL("Vel")]
    base = base_stats(pokemon)
    raw_ivs = pokemon.iv rescue []
    raw_evs = pokemon.ev rescue []
    ivs = ordered_stat_array(raw_ivs)
    evs = ordered_stat_array(raw_evs)
    stats = real_stats(pokemon)
    name_x = x + 8
    base_x = x + 70
    iv_x = x + 108
    ev_x = x + 146
    stats_x = x + width - 28
    old_size = bitmap.font.size rescue nil
    bitmap.font.size = 13 if bitmap.respond_to?(:font) && bitmap.font
    draw_text(bitmap, _INTL("Base"), base_x, y, 2)
    draw_text(bitmap, _INTL("IVs"), iv_x, y, 2)
    draw_text(bitmap, _INTL("EVs"), ev_x, y, 2)
    draw_text(bitmap, _INTL("Stats"), stats_x, y, 2)
    for i in 0...6
      row_y = y + 16 + i * 15
      draw_text(bitmap, names[i], name_x, row_y, 0)
      bitmap.fill_rect(base_x - 17, row_y + 1, 34, 14, stat_color(base[i]))
      draw_text(bitmap, base[i].to_i.to_s, base_x, row_y, 2, Color.new(30, 30, 30), Color.new(255, 255, 255))
      if include_real
        draw_text(bitmap, ivs[i].to_i.to_s, iv_x, row_y, 2)
        draw_text(bitmap, evs[i].to_i.to_s, ev_x, row_y, 2)
        draw_text(bitmap, stats[i].to_i.to_s, stats_x, row_y, 2)
      else
        draw_text(bitmap, "?", iv_x, row_y, 2)
        draw_text(bitmap, "?", ev_x, row_y, 2)
        draw_text(bitmap, "?", stats_x, row_y, 2)
      end
    end
    bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
  rescue Exception
  end

  def self.draw_type_icon_row_at(bitmap, label, ids, x, y, max_icons = 6)
    draw_text(bitmap, label, x, y, 0)
    ids = ids || []
    start_x = x + 64
    count = [ids.length, max_icons].min
    for i in 0...count
      draw_type_ico(bitmap, ids[i], start_x + i * 18, y, 16, 18)
    end
    if ids.length > max_icons
      draw_text(bitmap, "+" + (ids.length - max_icons).to_s, start_x + max_icons * 18, y, 0)
    end
  rescue Exception
  end

  def self.draw_footer_type_icon_group(bitmap, label, ids, x, y, max_icons = 4)
    draw_text(bitmap, label, x, y, 0, Color.new(248, 248, 248), Color.new(0, 0, 0, 0))
    ids = ids || []
    start_x = x + 38
    count = [ids.length, max_icons].min
    for i in 0...count
      draw_type_ico(bitmap, ids[i], start_x + i * 18, y, 16, 18)
    end
    if ids.length > max_icons
      draw_text(bitmap, "+" + (ids.length - max_icons).to_s, start_x + max_icons * 18, y, 0, Color.new(248, 248, 248), Color.new(0, 0, 0, 0))
    end
  rescue Exception
  end

  def self.all_real_type_ids
    ret = []
    return ret if !defined?(PBTypes)
    for type in 0..PBTypes.maxValue
      next if PBTypes.isPseudoType?(type) rescue false
      ret.push(type)
    end
    return ret
  rescue Exception
    return []
  end

  def self.type_chart_multiplier_key(chart, type)
    chart ||= {}
    ["x0", "x025", "x05", "x2", "x4"].each do |key|
      ids = chart[key] || []
      return key if ids.include?(type)
    end
    return "x1"
  rescue Exception
    return "x1"
  end

  def self.effectiveness_badge_data(key)
    case key.to_s
    when "x0"
      return ["0", Color.new(42, 42, 46), Color.new(248, 248, 248)]
    when "x025"
      return ["1/4", Color.new(138, 28, 28), Color.new(255, 238, 238)]
    when "x05"
      return ["1/2", Color.new(190, 52, 36), Color.new(255, 238, 220)]
    when "x2"
      return ["2", Color.new(105, 196, 28), Color.new(20, 56, 16)]
    when "x4"
      return ["4", Color.new(52, 152, 0), Color.new(248, 255, 232)]
    end
    return ["", nil, nil]
  rescue Exception
    return ["", nil, nil]
  end

  def self.draw_footer_type_chart(bitmap, chart, x, y, width)
    chart ||= {}
    ids = all_real_type_ids
    return if ids.length == 0
    cell_w = width.to_i / 9
    icon_w = 16
    icon_h = 18
    old_size = bitmap.font.size rescue nil
    bitmap.font.size = 10 if bitmap.respond_to?(:font) && bitmap.font
    for i in 0...ids.length
      row = i / 9
      col = i % 9
      cell_x = x + col * cell_w
      cell_y = y + row * 31
      icon_x = cell_x + (cell_w - icon_w) / 2
      draw_type_ico(bitmap, ids[i], icon_x, cell_y, icon_w, icon_h)
      key = type_chart_multiplier_key(chart, ids[i])
      label, fill, base = effectiveness_badge_data(key)
      next if label.to_s == "" || !fill
      badge_w = label.length > 1 ? 28 : 18
      badge_x = cell_x + (cell_w - badge_w) / 2
      badge_y = cell_y + 18
      bitmap.fill_rect(badge_x, badge_y, badge_w, 13, Color.new(238, 238, 238))
      bitmap.fill_rect(badge_x + 1, badge_y + 1, badge_w - 2, 11, fill)
      draw_text(bitmap, label, cell_x + cell_w / 2, badge_y - 1, 2, base || Color.new(248, 248, 248), Color.new(0, 0, 0, 0))
    end
    bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
  rescue Exception
    bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
  end

  def self.draw_detail_row(bitmap, text, x, y, width, selected)
    if selected
      bitmap.fill_rect(x, y, width, 17, Color.new(255, 232, 96))
      bitmap.fill_rect(x + 1, y + 1, width - 2, 15, Color.new(255, 248, 176))
    end
    draw_text(bitmap, fit_text(bitmap, text, width - 8), x + 4, y - 1, 0)
  rescue Exception
  end

  def self.draw_moves_at(bitmap, pokemon, x, y, width, selected_move = -1)
    moves = pokemon.moves rescue []
    old_size = bitmap.font.size rescue nil
    bitmap.font.size = 12 if bitmap.respond_to?(:font) && bitmap.font
    draw_text(bitmap, _INTL("Movimientos"), x, y, 0)
    for i in 0...4
      move = moves[i] rescue nil
      next if !move || (move.id.to_i rescue 0) <= 0
      row_y = y + 18 + i * 25
      selected = selected_move.to_i == i
      edge = selected ? Color.new(255, 216, 64) : Color.new(222, 230, 236)
      fill = selected ? Color.new(255, 248, 180) : Color.new(248, 250, 252)
      bitmap.fill_rect(x, row_y, width, 25, edge)
      bitmap.fill_rect(x + 1, row_y + 1, width - 2, 23, fill)
      data = move_data(move)
      draw_sheet_icon(bitmap, type_icon_bitmap, (move.type.to_i rescue (data ? data.type.to_i : -1)), x + 2, row_y + 5, 31, 14)
      draw_sheet_icon(bitmap, category_icon_bitmap, (data ? data.category.to_i : -1), x + 36, row_y + 5, 28, 14)
      move_name = PBMoves.getName(move.id).to_s rescue move.name.to_s
      draw_text(bitmap, fit_text(bitmap, move_name, width - 156), x + 68, row_y + 1, 0)
      pp = move.totalpp.to_i > 0 ? _INTL("{1}/{2}", move.pp.to_i, move.totalpp.to_i) : "---"
      draw_text(bitmap, _INTL("PP {1}", pp), x + width - 72, row_y + 1, 0)
      draw_text(bitmap, _INTL("Pot {1}", move_power_text(move)), x + width - 72, row_y + 11, 0)
    end
    bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
  rescue Exception
  end

  def self.draw_detail_header(bitmap, pokemon, x, y, width, selected)
    if selected
      bitmap.fill_rect(x + 10, y + 6, width - 20, 22, Color.new(255, 232, 96))
      bitmap.fill_rect(x + 11, y + 7, width - 22, 20, Color.new(255, 248, 176))
    end
    title = _INTL("{1} Nv.{2}", pokemon_name(pokemon), (pokemon.level.to_i rescue 1))
    ids = type_ids(pokemon)
    title_width = bitmap.text_size(title).width rescue 120
    icon_width = ids.length > 0 ? ids.length * 15 + (ids.length - 1) * 3 : 0
    total_width = title_width + (icon_width > 0 ? 8 + icon_width : 0)
    start_x = x + (width - total_width) / 2
    draw_text(bitmap, title, start_x, y + 8, 0)
    draw_type_icons_compact(bitmap, pokemon, start_x + title_width + 8, y + 10, 15, 17) if icon_width > 0
  rescue Exception
  end

  def self.draw_half_detail(bitmap, session, local_party, remote_party, detail_index, detail_cursor = 0)
    own_side = detail_index.to_i < 6
    pokemon = own_side ? (local_party[detail_index.to_i] rescue nil) : (remote_party[detail_index.to_i - 6] rescue nil)
    return if !pokemon
    x = own_side ? 4 : half_width + 4
    y = 28
    width = half_width - 8
    height = 288
    draw_box(bitmap, x, y, width, height, Color.new(238, 242, 246), Color.new(40, 80, 112))
    draw_detail_header(bitmap, pokemon, x, y, width, detail_cursor.to_i == 0)
    ability = ability_name(pokemon)
    item = item_name(pokemon)
    draw_detail_row(bitmap, _INTL("Hab: {1}", ability), x + 10, y + 24, width - 20, detail_cursor.to_i == 1)
    draw_detail_row(bitmap, _INTL("Obj: {1}", item), x + 10, y + 42, width - 20, detail_cursor.to_i == 2)
    draw_stat_table_at(bitmap, pokemon, true, x + 6, y + 56, width - 12)
    selected_move = detail_cursor.to_i >= 3 ? detail_cursor.to_i - 3 : -1
    draw_moves_at(bitmap, pokemon, x + 12, y + 166, width - 24, selected_move)
  rescue Exception
  end

  def self.detail_pokemon(local_party, remote_party, detail_index)
    return nil if detail_index == nil
    return local_party[detail_index.to_i] if detail_index.to_i < 6
    return remote_party[detail_index.to_i - 6]
  rescue Exception
    return nil
  end

  def self.draw_preview_footer(bitmap, detail_index = nil, detail_cursor = 0, local_party = nil, remote_party = nil, confirm_selected = false, details_open = false)
    detail_mode = details_open || detail_index != nil
    footer_width = detail_mode ? Graphics.width - 8 : Graphics.width - 120
    bitmap.fill_rect(4, 312, footer_width, 72, Color.new(52, 68, 84))
    bitmap.fill_rect(6, 314, footer_width - 4, 68, Color.new(68, 84, 104))
    if !detail_mode
      button_edge = confirm_selected ? Color.new(255, 232, 64) : Color.new(28, 48, 84)
      button_fill = confirm_selected ? Color.new(60, 164, 72) : Color.new(48, 120, 220)
      bitmap.fill_rect(Graphics.width - 110, 326, 104, 42, button_edge)
      bitmap.fill_rect(Graphics.width - 107, 329, 98, 36, button_fill)
    end
    old_size = bitmap.font.size rescue nil
    if detail_index
      pokemon = detail_pokemon(local_party, remote_party, detail_index)
      entry = detail_entry(pokemon, detail_cursor)
      bitmap.font.size = 13 if bitmap.respond_to?(:font) && bitmap.font
      if entry[:kind] == :type_chart
        bitmap.font.size = 12 if bitmap.respond_to?(:font) && bitmap.font
        draw_footer_type_chart(bitmap, entry[:chart], 20, 316, Graphics.width - 40)
      else
        draw_text(bitmap, fit_text(bitmap, entry[:title].to_s, Graphics.width - 40), 20, 318, 0, Color.new(248, 248, 248), Color.new(0, 0, 0, 0))
        draw_text(bitmap, fit_text(bitmap, entry[:subtitle].to_s, Graphics.width - 40), 20, 334, 0, Color.new(232, 240, 248), Color.new(0, 0, 0, 0)) if entry[:subtitle].to_s != ""
        draw_wrapped_text(bitmap, entry[:description].to_s, 20, entry[:subtitle].to_s == "" ? 338 : 350, Graphics.width - 40, entry[:subtitle].to_s == "" ? 2 : 1, Color.new(248, 248, 248), Color.new(0, 0, 0, 0))
        bitmap.font.size = 12 if bitmap.respond_to?(:font) && bitmap.font
        draw_text(bitmap, _INTL("Arriba/abajo: info   F3: PokemonDB   Y: guardar   B: volver"), 20, 368, 0, Color.new(248, 248, 248), Color.new(0, 0, 0, 0))
      end
    elsif details_open
      bitmap.font.size = 15 if bitmap.respond_to?(:font) && bitmap.font
      draw_text(bitmap, _INTL("Puedes comparar ambos equipos sin cerrar detalles."), 20, 324, 0, Color.new(248, 248, 248), Color.new(0, 0, 0, 0))
      draw_text(bitmap, _INTL("A: abrir detalles del seleccionado   B: cerrar detalles"), 20, 350, 0, Color.new(248, 248, 248), Color.new(0, 0, 0, 0))
    else
      bitmap.font.size = 16 if bitmap.respond_to?(:font) && bitmap.font
      draw_text(bitmap, _INTL("Elige un Pokemon o baja hasta CONFIRMAR."), 28, 326, 0, Color.new(248, 248, 248), Color.new(0, 0, 0, 0))
      draw_text(bitmap, _INTL("A: detalles/confirmar   Y: guardar equipo   B: cancelar"), 28, 352, 0, Color.new(248, 248, 248), Color.new(0, 0, 0, 0))
    end
    if !detail_mode
      bitmap.font.size = 14 if bitmap.respond_to?(:font) && bitmap.font
      draw_text(bitmap, _INTL("CONFIRMAR"), Graphics.width - 58, 340, 2, Color.new(248, 248, 248), Color.new(0, 0, 0, 0))
    end
    bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
  rescue Exception
  end

  def self.draw_preview(bitmap, session, local_party, remote_party, selected, detail_indexes = nil, detail_cursors = nil)
    bitmap.clear
    draw_party_background(bitmap)
    pbSetSystemFont(bitmap) if defined?(pbSetSystemFont)
    apply_preview_font(bitmap)
    bitmap.font.size = 18 if bitmap.respond_to?(:font) && bitmap.font
    draw_text(bitmap, _INTL("Mi equipo"), half_width / 2, 4, 2, Color.new(248, 248, 248), Color.new(0, 0, 0))
    draw_text(bitmap, _INTL("Equipo de {1}", session[:remote_name].to_s), half_width + half_width / 2, 4, 2, Color.new(248, 248, 248), Color.new(0, 0, 0))
    bitmap.font.size = 14 if bitmap.respond_to?(:font) && bitmap.font
    draw_team_cells(bitmap, local_party, 0, selected)
    draw_team_cells(bitmap, remote_party, 6, selected)
    detail_values = detail_indexes_array(detail_indexes)
    cursor_values = detail_cursors.is_a?(Array) ? detail_cursors : [detail_cursors.to_i, detail_cursors.to_i]
    draw_half_detail(bitmap, session, local_party, remote_party, detail_values[0], cursor_values[0]) if detail_values[0] != nil
    draw_half_detail(bitmap, session, local_party, remote_party, detail_values[1], cursor_values[1]) if detail_values[1] != nil
    footer_detail = detail_for_selected(selected, detail_values)
    footer_cursor = footer_detail == nil ? 0 : cursor_values[team_half(footer_detail)].to_i
    footer_detail = detail_values[0] || detail_values[1] if footer_detail == nil && any_detail_open?(detail_values)
    footer_cursor = cursor_values[team_half(footer_detail)].to_i if footer_detail != nil
    draw_preview_footer(bitmap, footer_detail, footer_cursor, local_party, remote_party, selected.to_i == confirm_index, any_detail_open?(detail_values))
  rescue Exception
  end

  def self.set_preview_visible(overlay, icons, value)
    begin
      overlay.visible = value if overlay && overlay.respond_to?(:visible=)
    rescue Exception
    end
    begin
      if icons && icons.respond_to?(:values)
        for sprite in icons.values
          sprite.visible = value if sprite && sprite.respond_to?(:visible=)
        end
      end
    rescue Exception
    end
  end

  def self.confirm_preview_action(overlay, icons, message)
    set_preview_visible(overlay, icons, false)
    result = Kernel.pbConfirmMessage(message)
    set_preview_visible(overlay, icons, true)
    return result ? true : false
  rescue Exception
    set_preview_visible(overlay, icons, true)
    return false
  end

  def self.button_y_trigger?
    return true if defined?(SebiControls) && SebiControls.button_y_trigger?
    return Input.trigger?(Input::Y) if defined?(Input::Y)
    return false
  rescue Exception
    return false
  end

  def self.save_visible_team_action(overlay, icons, left_party, right_party, selected, left_title, right_title)
    return false if !defined?(SebiSavedTeams)
    set_preview_visible(overlay, icons, false)
    commands = [
      _INTL("Guardar {1}", left_title.to_s == "" ? _INTL("equipo izquierdo") : left_title.to_s),
      _INTL("Guardar {1}", right_title.to_s == "" ? _INTL("equipo derecho") : right_title.to_s),
      _INTL("Abrir gestor de equipos"),
      _INTL("Cancelar")
    ]
    cmd = Kernel.pbMessage(_INTL("Guardar equipo en formato Showdown"), commands, commands.length)
    if cmd == 0
      SebiSavedTeams.save_party(left_party, left_title)
    elsif cmd == 1
      SebiSavedTeams.save_party(right_party, right_title)
    elsif cmd == 2
      SebiSavedTeams.open_manager
    end
    set_preview_visible(overlay, icons, true)
    return true
  rescue Exception
    set_preview_visible(overlay, icons, true)
    return false
  end

  def self.show_preview(session, local_party, remote_party)
    viewport = nil
    overlay = nil
    icons = {}
    viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    viewport.z = 99999
    overlay = BitmapSprite.new(Graphics.width, Graphics.height, viewport)
    overlay.z = 1
    icons = create_icons(local_party, remote_party, viewport)
    indexes = valid_indexes(local_party, remote_party)
    return false if indexes.length == 0
    selected = indexes[0]
    last_pokemon_index = selected
    detail_indexes = [nil, nil]
    detail_cursors = [0, 0]
    draw_preview(overlay.bitmap, session, local_party, remote_party, selected, detail_indexes, detail_cursors)
    loop do
      Graphics.update
      Input.update
      update_icons(icons, selected, detail_indexes)
      old_selected = selected
      old_details = detail_indexes.clone
      old_cursors = detail_cursors.clone
      a_triggered = (defined?(SebiControls) && SebiControls.button_a_trigger?) || Input.trigger?(Input::C)
      b_triggered = (defined?(SebiControls) && SebiControls.button_b_trigger?) || Input.trigger?(Input::B)
      y_triggered = button_y_trigger?
      db_triggered = false
      db_triggered = SebiControls.db_trigger? if defined?(SebiControls)
      db_triggered = true if !db_triggered && defined?(Input::F3) && Input.trigger?(Input::F3)
      details_open = any_detail_open?(detail_indexes)
      selected_half = selected.to_i == confirm_index ? 0 : team_half(selected)
      active_detail = selected.to_i == confirm_index ? nil : detail_indexes[selected_half]
      if details_open
        if y_triggered
          save_visible_team_action(overlay, icons, local_party, remote_party, selected, _INTL("Mi equipo"), _INTL("Equipo de {1}", session[:remote_name].to_s))
        elsif db_triggered
          pokemon = detail_pokemon(local_party, remote_party, active_detail || detail_indexes[0] || detail_indexes[1])
          SebiPokemonDB.open_pokemon(pokemon) if pokemon && defined?(SebiPokemonDB)
        elsif b_triggered
          if active_detail != nil
            detail_indexes[selected_half] = nil
            detail_cursors[selected_half] = 0
          else
            detail_indexes = [nil, nil]
            detail_cursors = [0, 0]
          end
          pbPlayCancelSE() if defined?(pbPlayCancelSE)
        elsif Input.trigger?(Input::LEFT) || Input.trigger?(Input::RIGHT)
          direction = Input.trigger?(Input::LEFT) ? :previous : :next
          base_index = index_valid?(selected, local_party, remote_party) ? selected : (active_detail || detail_indexes[0] || detail_indexes[1] || indexes[0])
          new_index = next_index(base_index, direction, local_party, remote_party)
          if new_index.to_i != selected.to_i && index_valid?(new_index, local_party, remote_party)
            selected = new_index
            pbPlayCursorSE() if defined?(pbPlayCursorSE)
          end
        elsif Input.trigger?(Input::UP) || Input.trigger?(Input::DOWN)
          if active_detail != nil && selected.to_i == active_detail.to_i
            pokemon = detail_pokemon(local_party, remote_party, active_detail)
            count = detail_entry_count(pokemon)
            count = 1 if count <= 0
            if Input.trigger?(Input::UP)
              detail_cursors[selected_half] = (detail_cursors[selected_half].to_i - 1) % count
            else
              detail_cursors[selected_half] = (detail_cursors[selected_half].to_i + 1) % count
            end
          else
            selected = next_index(selected, Input.trigger?(Input::UP) ? :up : :down, local_party, remote_party)
          end
          pbPlayCursorSE() if defined?(pbPlayCursorSE)
        elsif a_triggered && selected.to_i != confirm_index && index_valid?(selected, local_party, remote_party)
          half = team_half(selected)
          detail_indexes[half] = selected
          pokemon = detail_pokemon(local_party, remote_party, selected)
          count = detail_entry_count(pokemon)
          count = 1 if count <= 0
          detail_cursors[half] = 0 if detail_cursors[half].to_i < 0 || detail_cursors[half].to_i >= count
          pbPlayDecisionSE() if defined?(pbPlayDecisionSE)
        end
      else
        if y_triggered
          save_visible_team_action(overlay, icons, local_party, remote_party, selected, _INTL("Mi equipo"), _INTL("Equipo de {1}", session[:remote_name].to_s))
        elsif selected.to_i == confirm_index
          if b_triggered
            return false if confirm_preview_action(overlay, icons, _INTL("Seguro que quieres salir de la vista previa del combate?"))
          elsif a_triggered
            return true if confirm_preview_action(overlay, icons, _INTL("Seguro que quieres confirmar este equipo?"))
          elsif Input.trigger?(Input::UP)
            selected = index_valid?(last_pokemon_index, local_party, remote_party) ? last_pokemon_index : indexes[0]
          end
        elsif Input.trigger?(Input::LEFT)
          selected = next_index_for_preview(selected, :previous, local_party, remote_party)
        elsif Input.trigger?(Input::RIGHT)
          selected = next_index_for_preview(selected, :next, local_party, remote_party)
        elsif Input.trigger?(Input::UP)
          selected = next_index_for_preview(selected, :up, local_party, remote_party)
        elsif Input.trigger?(Input::DOWN)
          selected = next_index_for_preview(selected, :down, local_party, remote_party)
        elsif b_triggered
          return false if confirm_preview_action(overlay, icons, _INTL("Seguro que quieres salir de la vista previa del combate?"))
        elsif a_triggered
          half = team_half(selected)
          detail_indexes[half] = selected
          detail_cursors[half] = 0
          pbPlayDecisionSE() if defined?(pbPlayDecisionSE)
        end
      end
      last_pokemon_index = selected if selected.to_i != confirm_index && index_valid?(selected, local_party, remote_party)
      if old_selected.to_i != selected.to_i
        pbPlayCursorSE() if defined?(pbPlayCursorSE)
        draw_preview(overlay.bitmap, session, local_party, remote_party, selected, detail_indexes, detail_cursors)
      elsif old_details != detail_indexes || old_cursors != detail_cursors
        draw_preview(overlay.bitmap, session, local_party, remote_party, selected, detail_indexes, detail_cursors)
      end
    end
  rescue Exception
    SebiVisualMultiplayer.log("pvp preview failed: " + $!.class.to_s + ": " + $!.message.to_s) if defined?(SebiVisualMultiplayer)
    return false
  ensure
    begin
      for sprite in icons.values
        sprite.dispose if sprite && !sprite.disposed?
      end
      overlay.bitmap.dispose if overlay && overlay.bitmap && !overlay.bitmap.disposed?
      overlay.dispose if overlay && !overlay.disposed?
      viewport.dispose if viewport && !viewport.disposed?
    rescue Exception
    end
  end

  def self.draw_readonly_team(bitmap, title, party, selected, detail_index = nil, detail_cursor = 0)
    bitmap.clear
    draw_party_background(bitmap)
    pbSetSystemFont(bitmap) if defined?(pbSetSystemFont)
    apply_preview_font(bitmap)
    bitmap.font.size = 18 if bitmap.respond_to?(:font) && bitmap.font
    draw_text(bitmap, title.to_s == "" ? _INTL("Equipo observado") : title.to_s, half_width / 2, 4, 2, Color.new(248, 248, 248), Color.new(0, 0, 0))
    bitmap.font.size = 14 if bitmap.respond_to?(:font) && bitmap.font
    draw_team_cells(bitmap, party, 0, selected)
    draw_half_detail(bitmap, {}, party, [], detail_index, detail_cursor) if detail_index != nil
    if detail_index != nil
      draw_preview_footer(bitmap, detail_index, detail_cursor, party, [], false, true)
    else
      footer_y = Graphics.height - 72
      bitmap.fill_rect(4, footer_y, Graphics.width - 8, 68, Color.new(68, 84, 104))
      bitmap.fill_rect(8, footer_y + 4, Graphics.width - 16, 60, Color.new(68, 84, 104))
      draw_text(bitmap, _INTL("A: detalles   Y: guardar equipo   B: volver"), 36, footer_y + 18, 0, Color.new(248, 248, 248), Color.new(32, 32, 40))
    end
  rescue Exception
  end

  def self.draw_readonly_teams(bitmap, left_title, left_party, right_title, right_party, selected, detail_indexes = nil, detail_cursors = nil)
    bitmap.clear
    draw_party_background(bitmap)
    pbSetSystemFont(bitmap) if defined?(pbSetSystemFont)
    apply_preview_font(bitmap)
    bitmap.font.size = 18 if bitmap.respond_to?(:font) && bitmap.font
    draw_text(bitmap, left_title.to_s == "" ? _INTL("Equipo observado") : left_title.to_s, half_width / 2, 4, 2, Color.new(248, 248, 248), Color.new(0, 0, 0))
    draw_text(bitmap, right_title.to_s == "" ? _INTL("Equipo rival") : right_title.to_s, half_width + half_width / 2, 4, 2, Color.new(248, 248, 248), Color.new(0, 0, 0))
    bitmap.font.size = 14 if bitmap.respond_to?(:font) && bitmap.font
    draw_team_cells(bitmap, left_party, 0, selected)
    draw_team_cells(bitmap, right_party, 6, selected)
    detail_values = detail_indexes_array(detail_indexes)
    cursor_values = detail_cursors.is_a?(Array) ? detail_cursors : [detail_cursors.to_i, detail_cursors.to_i]
    draw_half_detail(bitmap, {}, left_party, right_party, detail_values[0], cursor_values[0]) if detail_values[0] != nil
    draw_half_detail(bitmap, {}, left_party, right_party, detail_values[1], cursor_values[1]) if detail_values[1] != nil
    footer_detail = detail_for_selected(selected, detail_values)
    footer_cursor = footer_detail == nil ? 0 : cursor_values[team_half(footer_detail)].to_i
    footer_detail = detail_values[0] || detail_values[1] if footer_detail == nil && any_detail_open?(detail_values)
    footer_cursor = cursor_values[team_half(footer_detail)].to_i if footer_detail != nil
    if any_detail_open?(detail_values)
      draw_preview_footer(bitmap, footer_detail, footer_cursor, left_party, right_party, false, true)
    else
      footer_y = Graphics.height - 72
      bitmap.fill_rect(4, footer_y, Graphics.width - 8, 68, Color.new(68, 84, 104))
      bitmap.fill_rect(8, footer_y + 4, Graphics.width - 16, 60, Color.new(68, 84, 104))
      draw_text(bitmap, _INTL("A: detalles   Y: guardar equipo   B: volver"), 36, footer_y + 18, 0, Color.new(248, 248, 248), Color.new(32, 32, 40))
    end
  rescue Exception
  end

  def self.show_readonly_teams(left_title, left_party, right_title, right_party)
    left_party = [] if !left_party
    right_party = [] if !right_party
    return if left_party.length == 0 && right_party.length == 0
    viewport = nil
    overlay = nil
    icons = {}
    viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    viewport.z = 99999
    overlay = BitmapSprite.new(Graphics.width, Graphics.height, viewport)
    overlay.z = 1
    icons = create_icons(left_party, right_party, viewport)
    indexes = valid_indexes(left_party, right_party)
    return if indexes.length == 0
    selected = indexes[0]
    detail_indexes = [nil, nil]
    detail_cursors = [0, 0]
    draw_readonly_teams(overlay.bitmap, left_title, left_party, right_title, right_party, selected, detail_indexes, detail_cursors)
    loop do
      Graphics.update
      Input.update
      update_icons(icons, selected, detail_indexes)
      old_selected = selected
      old_details = detail_indexes.clone
      old_cursors = detail_cursors.clone
      a_triggered = (defined?(SebiControls) && SebiControls.button_a_trigger?) || Input.trigger?(Input::C)
      b_triggered = (defined?(SebiControls) && SebiControls.button_b_trigger?) || Input.trigger?(Input::B)
      y_triggered = button_y_trigger?
      db_triggered = false
      db_triggered = SebiControls.db_trigger? if defined?(SebiControls)
      db_triggered = true if !db_triggered && defined?(Input::F3) && Input.trigger?(Input::F3)
      details_open = any_detail_open?(detail_indexes)
      selected_half = team_half(selected)
      active_detail = detail_indexes[selected_half]
      if details_open
        if y_triggered
          save_visible_team_action(overlay, icons, left_party, right_party, selected, left_title, right_title)
        elsif db_triggered
          pokemon = detail_pokemon(left_party, right_party, active_detail || detail_indexes[0] || detail_indexes[1])
          SebiPokemonDB.open_pokemon(pokemon) if pokemon && defined?(SebiPokemonDB)
        elsif b_triggered
          if active_detail != nil
            detail_indexes[selected_half] = nil
            detail_cursors[selected_half] = 0
          else
            detail_indexes = [nil, nil]
            detail_cursors = [0, 0]
          end
          pbPlayCancelSE() if defined?(pbPlayCancelSE)
        elsif Input.trigger?(Input::LEFT) || Input.trigger?(Input::RIGHT)
          direction = Input.trigger?(Input::LEFT) ? :previous : :next
          base_index = index_valid?(selected, left_party, right_party) ? selected : (active_detail || detail_indexes[0] || detail_indexes[1] || indexes[0])
          selected = next_index(base_index, direction, left_party, right_party)
          pbPlayCursorSE() if defined?(pbPlayCursorSE)
        elsif Input.trigger?(Input::UP) || Input.trigger?(Input::DOWN)
          if active_detail != nil && selected.to_i == active_detail.to_i
            pokemon = detail_pokemon(left_party, right_party, active_detail)
            count = detail_entry_count(pokemon)
            count = 1 if count <= 0
            detail_cursors[selected_half] = Input.trigger?(Input::UP) ? ((detail_cursors[selected_half].to_i - 1) % count) : ((detail_cursors[selected_half].to_i + 1) % count)
          else
            selected = next_index(selected, Input.trigger?(Input::UP) ? :up : :down, left_party, right_party)
          end
          pbPlayCursorSE() if defined?(pbPlayCursorSE)
        elsif a_triggered && index_valid?(selected, left_party, right_party)
          half = team_half(selected)
          detail_indexes[half] = selected
          detail_cursors[half] = 0
          pbPlayDecisionSE() if defined?(pbPlayDecisionSE)
        end
      else
        if y_triggered
          save_visible_team_action(overlay, icons, left_party, right_party, selected, left_title, right_title)
        elsif b_triggered
          break
        elsif Input.trigger?(Input::LEFT)
          selected = next_index(selected, :previous, left_party, right_party)
        elsif Input.trigger?(Input::RIGHT)
          selected = next_index(selected, :next, left_party, right_party)
        elsif Input.trigger?(Input::UP)
          selected = next_index(selected, :up, left_party, right_party)
        elsif Input.trigger?(Input::DOWN)
          selected = next_index(selected, :down, left_party, right_party)
        elsif a_triggered
          half = team_half(selected)
          detail_indexes[half] = selected
          detail_cursors[half] = 0
          pbPlayDecisionSE() if defined?(pbPlayDecisionSE)
        end
      end
      if old_selected.to_i != selected.to_i || old_details != detail_indexes || old_cursors != detail_cursors
        pbPlayCursorSE() if old_selected.to_i != selected.to_i && defined?(pbPlayCursorSE)
        draw_readonly_teams(overlay.bitmap, left_title, left_party, right_title, right_party, selected, detail_indexes, detail_cursors)
      end
    end
  rescue Exception
    SebiVisualMultiplayer.log("spectator teams preview failed: " + $!.class.to_s + ": " + $!.message.to_s) if defined?(SebiVisualMultiplayer)
  ensure
    begin
      for sprite in icons.values
        sprite.dispose if sprite && !sprite.disposed?
      end
      overlay.bitmap.dispose if overlay && overlay.bitmap && !overlay.bitmap.disposed?
      overlay.dispose if overlay && !overlay.disposed?
      viewport.dispose if viewport && !viewport.disposed?
    rescue Exception
    end
  end

  def self.show_readonly_team(title, party)
    return if !party || party.length == 0
    viewport = nil
    overlay = nil
    icons = {}
    viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    viewport.z = 99999
    overlay = BitmapSprite.new(Graphics.width, Graphics.height, viewport)
    overlay.z = 1
    icons = create_icons(party, [], viewport)
    indexes = indexes_for_half(0, party, [])
    return if indexes.length == 0
    selected = indexes[0]
    detail_index = nil
    detail_cursor = 0
    draw_readonly_team(overlay.bitmap, title, party, selected, detail_index, detail_cursor)
    loop do
      Graphics.update
      Input.update
      update_icons(icons, selected, detail_index)
      old_selected = selected
      old_detail = detail_index
      old_cursor = detail_cursor
      a_triggered = (defined?(SebiControls) && SebiControls.button_a_trigger?) || Input.trigger?(Input::C)
      b_triggered = (defined?(SebiControls) && SebiControls.button_b_trigger?) || Input.trigger?(Input::B)
      y_triggered = button_y_trigger?
      db_triggered = false
      db_triggered = SebiControls.db_trigger? if defined?(SebiControls)
      db_triggered = true if !db_triggered && defined?(Input::F3) && Input.trigger?(Input::F3)
      if detail_index != nil
        if y_triggered
          save_visible_team_action(overlay, icons, party, [], selected, title, "")
        elsif db_triggered
          pokemon = detail_pokemon(party, [], detail_index)
          SebiPokemonDB.open_pokemon(pokemon) if pokemon && defined?(SebiPokemonDB)
        elsif b_triggered
          detail_index = nil
          detail_cursor = 0
          pbPlayCancelSE() if defined?(pbPlayCancelSE)
        elsif Input.trigger?(Input::UP) || Input.trigger?(Input::DOWN)
          pokemon = detail_pokemon(party, [], detail_index)
          count = detail_entry_count(pokemon)
          count = 1 if count <= 0
          detail_cursor = Input.trigger?(Input::UP) ? ((detail_cursor.to_i - 1) % count) : ((detail_cursor.to_i + 1) % count)
          pbPlayCursorSE() if defined?(pbPlayCursorSE)
        end
      else
        if y_triggered
          save_visible_team_action(overlay, icons, party, [], selected, title, "")
        elsif b_triggered
          break
        elsif Input.trigger?(Input::UP)
          selected = next_index(selected, :up, party, [])
        elsif Input.trigger?(Input::DOWN)
          selected = next_index(selected, :down, party, [])
        elsif a_triggered
          detail_index = selected
          detail_cursor = 0
          pbPlayDecisionSE() if defined?(pbPlayDecisionSE)
        end
      end
      if old_selected.to_i != selected.to_i
        pbPlayCursorSE() if defined?(pbPlayCursorSE)
        draw_readonly_team(overlay.bitmap, title, party, selected, detail_index, detail_cursor)
      elsif old_detail != detail_index || old_cursor.to_i != detail_cursor.to_i
        draw_readonly_team(overlay.bitmap, title, party, selected, detail_index, detail_cursor)
      end
    end
  rescue Exception
    SebiVisualMultiplayer.log("spectator team preview failed: " + $!.class.to_s + ": " + $!.message.to_s) if defined?(SebiVisualMultiplayer)
  ensure
    begin
      for sprite in icons.values
        sprite.dispose if sprite && !sprite.disposed?
      end
      overlay.bitmap.dispose if overlay && overlay.bitmap && !overlay.bitmap.disposed?
      overlay.dispose if overlay && !overlay.disposed?
      viewport.dispose if viewport && !viewport.disposed?
    rescue Exception
    end
  end

  def self.show_single_pokemon_details(title, pokemon)
    return if !pokemon
    party = [pokemon]
    viewport = nil
    overlay = nil
    icons = {}
    viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    viewport.z = 99999
    overlay = BitmapSprite.new(Graphics.width, Graphics.height, viewport)
    overlay.z = 1
    icons = create_icons(party, [], viewport)
    selected = 0
    detail_index = 0
    detail_cursor = 0
    draw_readonly_team(overlay.bitmap, title, party, selected, detail_index, detail_cursor)
    loop do
      Graphics.update
      Input.update
      update_icons(icons, selected, detail_index)
      old_cursor = detail_cursor
      b_triggered = (defined?(SebiControls) && SebiControls.button_b_trigger?) || Input.trigger?(Input::B)
      db_triggered = false
      db_triggered = SebiControls.db_trigger? if defined?(SebiControls)
      db_triggered = true if !db_triggered && defined?(Input::F3) && Input.trigger?(Input::F3)
      if db_triggered
        SebiPokemonDB.open_pokemon(pokemon) if defined?(SebiPokemonDB)
      elsif b_triggered
        pbPlayCancelSE() if defined?(pbPlayCancelSE)
        break
      elsif Input.trigger?(Input::UP) || Input.trigger?(Input::DOWN)
        count = detail_entry_count(pokemon)
        count = 1 if count <= 0
        detail_cursor = Input.trigger?(Input::UP) ? ((detail_cursor.to_i - 1) % count) : ((detail_cursor.to_i + 1) % count)
        pbPlayCursorSE() if defined?(pbPlayCursorSE)
      end
      draw_readonly_team(overlay.bitmap, title, party, selected, detail_index, detail_cursor) if old_cursor.to_i != detail_cursor.to_i
    end
  rescue Exception
    SebiVisualMultiplayer.log("single pokemon details failed: " + $!.class.to_s + ": " + $!.message.to_s) if defined?(SebiVisualMultiplayer)
  ensure
    begin
      for sprite in icons.values
        sprite.dispose if sprite && !sprite.disposed?
      end
      overlay.bitmap.dispose if overlay && overlay.bitmap && !overlay.bitmap.disposed?
      overlay.dispose if overlay && !overlay.disposed?
      viewport.dispose if viewport && !viewport.disposed?
    rescue Exception
    end
  end

  def self.confirm_team(session, local_party, remote_party)
    return false if !session
    return show_preview(session, local_party, remote_party)
  rescue Exception
    return false
  end
end

module SebiBattleHistory
  @current = nil
  @last_choice_key = nil

  def self.safe(default_value = nil)
    return yield
  rescue Exception
    return default_value
  end

  def self.battle_key(battle)
    return battle.object_id if battle
    return nil
  rescue Exception
    return nil
  end

  def self.same_battle?(battle)
    return false if !@current || !battle
    return @current["battleKey"].to_i == battle_key(battle).to_i
  rescue Exception
    return false
  end

  def self.simple_pokemon(pokemon, index)
    return nil if !pokemon
    species = safe(0) { pokemon.species.to_i }
    return {
      "index" => index,
      "species" => species,
      "speciesName" => safe("") { PBSpecies.getName(species).to_s },
      "nickname" => safe("") { pokemon.name.to_s },
      "level" => safe(1) { pokemon.level.to_i },
      "hp" => safe(0) { pokemon.hp.to_i },
      "totalhp" => safe(0) { pokemon.totalhp.to_i },
      "status" => safe(0) { pokemon.status.to_i },
      "statusName" => defined?(SebiBattleAdvisor) ? SebiBattleAdvisor.status_name(safe(0) { pokemon.status.to_i }) : ""
    }
  rescue Exception
    return nil
  end

  def self.simple_party(party)
    ret = []
    return ret if !party
    for i in 0...party.length
      data = simple_pokemon(party[i], i)
      ret.push(data) if data
    end
    return ret
  rescue Exception
    return ret || []
  end

  def self.active_state(battle)
    ret = []
    for battler in safe([]) { battle.battlers }
      next if !battler
      pokemon = safe(nil) { battler.pokemon }
      species = safe(0) { pokemon.species.to_i }
      ret.push({
        "index" => safe(-1) { battler.index.to_i },
        "partyIndex" => safe(-1) { battler.pokemonIndex.to_i },
        "side" => safe(false) { battle.pbIsOpposing?(battler.index) } ? "rival" : "jugador",
        "species" => species,
        "speciesName" => safe("") { PBSpecies.getName(species).to_s },
        "name" => safe("") { battler.name.to_s },
        "level" => safe(1) { pokemon.level.to_i },
        "hp" => safe(0) { battler.hp.to_i },
        "totalhp" => safe(0) { battler.totalhp.to_i },
        "status" => safe(0) { battler.status.to_i },
        "statusName" => defined?(SebiBattleAdvisor) ? SebiBattleAdvisor.status_name(safe(0) { battler.status.to_i }) : "",
        "fainted" => safe(false) { battler.isFainted? ? true : false }
      })
    end
    return ret
  rescue Exception
    return ret || []
  end

  def self.compact_state(battle)
    return {
      "turn" => safe(0) { battle.turncount.to_i },
      "decision" => safe(0) { battle.decision.to_i },
      "activeBattlers" => active_state(battle),
      "playerParty" => simple_party(safe([]) { battle.party1 }),
      "opponentParty" => simple_party(safe([]) { battle.party2 })
    }
  rescue Exception
    return {}
  end

  def self.full_state(battle)
    return SebiBattleAdvisor.battle_state(battle) if defined?(SebiBattleAdvisor)
    return compact_state(battle)
  rescue Exception
    return compact_state(battle)
  end

  def self.start(battle)
    return if !battle
    @last_choice_key = nil
    initial = defined?(SebiBattleAdvisor) ? SebiBattleAdvisor.battle_state(battle) : compact_state(battle)
    @current = {
      "generatedAt" => Time.now.to_s,
      "source" => "Pokemon Z SebiLink Battle History",
      "battleKey" => battle_key(battle),
      "pvpBattle" => safe(false) { battle.instance_variable_get("@sebi_pvp_session") ? true : false },
      "doubleBattle" => safe(false) { battle.doublebattle ? true : false },
      "player" => defined?(SebiBattleAdvisor) ? SebiBattleAdvisor.trainer_data(safe(nil) { battle.player }) : nil,
      "opponent" => defined?(SebiBattleAdvisor) ? SebiBattleAdvisor.trainer_data(safe(nil) { battle.opponent }) : nil,
      "initialState" => initial,
      "turns" => [],
      "messages" => []
    }
  rescue Exception
    @current = nil
  end

  def self.clean_message(message)
    text = message.to_s
    text = text.gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "")
    return text.strip
  rescue Exception
    return ""
  end

  def self.record_message(battle, message)
    return if !same_battle?(battle)
    text = clean_message(message)
    return if text == ""
    messages = @current["messages"]
    return if messages.length > 0 && messages[-1]["text"].to_s == text
    entry = {
      "turn" => safe(0) { battle.turncount.to_i },
      "frame" => (Graphics.frame_count rescue 0),
      "text" => text
    }
    messages.push(entry)
    messages.shift while messages.length > 500
    turn = turn_entry(battle, true)
    if turn
      turn["messages"] = [] if !turn["messages"]
      last = turn["messages"][-1] rescue nil
      turn["messages"].push(entry) if !last || last["text"].to_s != text
    end
  rescue Exception
  end

  def self.turn_entry(battle, create = false)
    return nil if !same_battle?(battle)
    turn_number = safe(0) { battle.turncount.to_i }
    turns = @current["turns"]
    for entry in turns
      return entry if entry && entry["turn"].to_i == turn_number
    end
    return nil if !create
    entry = {
      "turn" => turn_number,
      "choices" => [],
      "messages" => [],
      "createdAtFrame" => (Graphics.frame_count rescue 0)
    }
    turns.push(entry)
    return entry
  rescue Exception
    return nil
  end

  def self.choice_data(battle, battler, choice)
    return nil if !battler || !choice
    kind = choice[0].to_i
    data = {
      "battlerIndex" => safe(-1) { battler.index.to_i },
      "side" => safe(false) { battle.pbIsOpposing?(battler.index) } ? "rival" : "jugador",
      "pokemon" => safe("") { battler.name.to_s },
      "kind" => kind
    }
    if kind == 1
      move = choice[2] rescue nil
      move_id = safe(0) { move.id.to_i }
      data["action"] = "move"
      data["moveId"] = move_id
      data["moveName"] = safe("") { PBMoves.getName(move_id).to_s }
      data["target"] = safe(-1) { choice[3].to_i }
    elsif kind == 2
      party_index = safe(-1) { choice[1].to_i }
      party = safe([]) { battle.pbParty(battler.index) }
      pokemon = party[party_index] rescue nil
      data["action"] = "switch"
      data["partyIndex"] = party_index
      data["switchTo"] = safe("") { pokemon.name.to_s }
    elsif kind == 3
      data["action"] = "item"
    elsif kind == 4
      data["action"] = "call"
    elsif kind == 5
      data["action"] = safe(false) { battle.instance_variable_get("@sebi_pvp_session") ? true : false } ? "skip" : "run"
    else
      data["action"] = "none"
    end
    return data
  rescue Exception
    return nil
  end

  def self.record_choices(battle)
    return if !same_battle?(battle)
    choices = safe([]) { battle.instance_variable_get("@choices") }
    entries = []
    for i in 0...choices.length
      battler = safe(nil) { battle.battlers[i] }
      data = choice_data(battle, battler, choices[i])
      entries.push(data) if data
    end
    key = safe(0) { battle.turncount.to_i }.to_s + ":" + entries.collect { |entry| entry["battlerIndex"].to_s + "-" + entry["action"].to_s + "-" + entry["moveId"].to_s + "-" + entry["partyIndex"].to_s }.join("|")
    return if @last_choice_key == key
    @last_choice_key = key
    turn = turn_entry(battle, true)
    return if !turn
    turn["choices"] = entries
    turn["beforeActions"] = compact_state(battle)
    turn["beforeActionsFull"] = full_state(battle)
    turn["choiceFrame"] = (Graphics.frame_count rescue 0)
  rescue Exception
  end

  def self.record_turn_end(battle)
    return if !same_battle?(battle)
    turn = turn_entry(battle, true)
    return if !turn
    turn["afterActions"] = compact_state(battle)
    turn["afterActionsFull"] = full_state(battle)
    turn["endFrame"] = (Graphics.frame_count rescue 0)
  rescue Exception
  end

  def self.recent_messages(limit = 20)
    return [] if !@current || !@current["messages"]
    start = @current["messages"].length - limit.to_i
    start = 0 if start < 0
    return @current["messages"][start, limit.to_i] || []
  rescue Exception
    return []
  end

  def self.finish(battle, result)
    return if !same_battle?(battle)
    @current["finishedAt"] = Time.now.to_s
    @current["result"] = result.to_i
    @current["finalState"] = compact_state(battle)
    @current["finalStateFull"] = full_state(battle)
    @current["schema"] = "turn-by-turn-full-state-v2"
    if defined?(SebiBattleAdvisor)
      SebiBattleAdvisor.ensure_runtime
      SebiBattleAdvisor.atomic_write(SebiBattleAdvisor.last_battle_history_path, SebiBattleAdvisor.json(@current))
    end
  rescue Exception
  ensure
    @current = nil
    @last_choice_key = nil
  end
end

module SebiBattleSpectator
  @subscribers = {}
  @pending_watches = {}
  @watching_id = nil
  @watching_token = nil
  @primary_view_id = nil
  @views = {}
  @viewer_pending = false
  @viewer_active = false
  @last_publish_frame = -9999
  @last_frame_publish_frame = -9999
  @state_sequence = 0
  @frame_sequence = 0
  @end_message = nil
  @capture_helper_started = false
  @capture_session = nil

  def self.runtime_dir
    return SebiLinkPaths.runtime_dir("battle-spectator") if defined?(SebiLinkPaths)
    return File.expand_path("multiplayer/battle-spectator/runtime")
  rescue Exception
    return "multiplayer/battle-spectator/runtime"
  end

  def self.state_path
    return File.join(runtime_dir, "state.json")
  end

  def self.ensure_runtime
    SebiLinkPaths.ensure_dir(runtime_dir) if defined?(SebiLinkPaths)
  rescue Exception
  end

  def self.write_state(state)
    return if !defined?(SebiBattleAdvisor)
    ensure_runtime
    SebiBattleAdvisor.atomic_write(state_path, SebiBattleAdvisor.json(state))
  rescue Exception
  end

  def self.safe_filename(value)
    return value.to_s.gsub(/[^A-Za-z0-9_-]/, "_")
  rescue Exception
    return "view"
  end

  def self.frame_path(view_id, token = nil)
    ensure_runtime
    token = @watching_token if token == nil || token.to_s == ""
    return File.join(runtime_dir, "frame_" + safe_filename(token) + "_" + safe_filename(view_id) + ".png")
  end

  def self.clear_received_frames
    return if !@views
    for view in @views.values
      path = view ? view[:path] : nil
      begin
        File.delete(path) if path && FileTest.exist?(path)
      rescue Exception
      end
    end
  end

  def self.watch(player)
    return if !player
    if !defined?(SebiVisualMultiplayer) || !SebiVisualMultiplayer.client.connected?
      Kernel.pbMessage(_INTL("No hay conexion con la sala multijugador."))
      return
    end
    stop_watching(false)
    clear_received_frames
    @watching_id = player.remote_id.to_s
    @watching_token = SebiVisualMultiplayer.make_token
    @primary_view_id = @watching_id
    @views = {}
    @viewer_pending = true
    @viewer_active = false
    @end_message = nil
    SebiVisualMultiplayer.client.send_direct(@watching_id, "SPECTATE_WATCH", [
      @watching_token,
      SebiVisualMultiplayer.escape(SebiVisualMultiplayer.local_name)
    ])
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir el modo espectador."))
  end

  def self.pending_watch_expired?(entry)
    frame = Graphics.frame_count rescue 0
    return frame - (entry[:frame].to_i rescue frame) > 600
  rescue Exception
    return false
  end

  def self.queue_watch(from_id, token, escaped_name)
    @pending_watches = {} if !@pending_watches
    @pending_watches[token.to_s] = {
      :remote_id => from_id.to_s,
      :name => (escaped_name ? SebiVisualMultiplayer.unescape(escaped_name.to_s) : ""),
      :escaped_name => escaped_name.to_s,
      :frame => (Graphics.frame_count rescue 0)
    }
  rescue Exception
  end

  def self.add_subscriber(token, from_id, escaped_name)
    @subscribers = {} if !@subscribers
    @subscribers[token.to_s] = {
      :remote_id => from_id.to_s,
      :name => (escaped_name ? SebiVisualMultiplayer.unescape(escaped_name.to_s) : ""),
      :escaped_name => escaped_name.to_s
    }
  rescue Exception
  end

  def self.register_pending_watches(battle)
    return if !battle || !@pending_watches || @pending_watches.length == 0
    for token in @pending_watches.keys
      entry = @pending_watches[token]
      if !entry || pending_watch_expired?(entry)
        @pending_watches.delete(token)
        next
      end
      @pending_watches.delete(token)
      @subscribers = {} if !@subscribers
      @subscribers[token.to_s] = entry
      publish_to(entry[:remote_id], token, battle, "joined")
      forward_join_to_pvp_opponent(battle, token, entry[:remote_id], entry[:escaped_name])
    end
  rescue Exception
  end

  def self.request(player)
    watch(player)
    open_viewer if @watching_token
  rescue Exception
  end

  def self.stop_watching(show_message = true)
    if @watching_id && @watching_token && defined?(SebiVisualMultiplayer)
      SebiVisualMultiplayer.client.send_direct(@watching_id, "SPECTATE_STOP", [@watching_token])
    end
    clear_received_frames
    @watching_id = nil
    @watching_token = nil
    @primary_view_id = nil
    @views = {}
    @viewer_pending = false
    state = {
      "generatedAt" => Time.now.to_s,
      "ended" => true,
      "message" => "Modo espectador detenido."
    }
    write_state(state)
    Kernel.pbMessage(_INTL("Modo espectador detenido.")) if show_message
  rescue Exception
  end

  def self.handle_watch(from_id, fields)
    token = fields[0].to_s
    battle = defined?(SebiLinkHub) ? SebiLinkHub.current_battle : nil
    if !battle
      queue_watch(from_id, token, fields[1])
      return
    end
    add_subscriber(token, from_id, fields[1])
    publish_to(from_id, token, battle, "joined")
    forward_join_to_pvp_opponent(battle, token, from_id, fields[1])
  rescue Exception
  end

  def self.handle_request(from_id, fields)
    handle_watch(from_id, fields)
  end

  def self.handle_state(from_id, fields)
    token = fields[0].to_s
    return if !@watching_token || token != @watching_token.to_s
    if fields.length >= 4
      view_id = fields[1].to_s
      view_name = SebiVisualMultiplayer.unescape(fields[2].to_s)
      encoded = fields[3].to_s
    else
      view_id = from_id.to_s
      view_name = from_id.to_s
      encoded = fields[1].to_s
    end
    state = SebiVisualMultiplayer.decode_object(encoded)
    @views = {} if !@views
    view = @views[view_id] || {}
    view[:name] = view_name
    view[:state] = state if state.is_a?(Hash)
    @state_sequence = (@state_sequence || 0) + 1
    view[:sequence] = @state_sequence
    @views[view_id] = view
    write_state(state)
    @viewer_pending = true
  rescue Exception
  end

  def self.handle_end(from_id, fields)
    token = fields[0].to_s
    return if !@watching_token || token != @watching_token.to_s
    message = fields[1] ? SebiVisualMultiplayer.unescape(fields[1].to_s) : _INTL("El combate ha terminado.")
    view = @views[from_id.to_s] if @views
    view[:ended] = true if view
    if from_id.to_s == @primary_view_id.to_s
      @end_message = message
      @watching_id = nil
      @watching_token = nil
      @viewer_pending = false
    end
  rescue Exception
  end

  def self.handle_stop(from_id, fields)
    token = fields[0].to_s
    battle = defined?(SebiLinkHub) ? SebiLinkHub.current_battle : nil
    @subscribers.delete(token) if @subscribers
    @pending_watches.delete(token) if @pending_watches
    forward_leave_to_pvp_opponent(battle, token)
    stop_capture_helper if !@subscribers || @subscribers.length == 0
  rescue Exception
  end

  def self.handle_join(from_id, fields)
    token = fields[0].to_s
    spectator_id = fields[1].to_s
    spectator_name = fields[2] ? SebiVisualMultiplayer.unescape(fields[2].to_s) : ""
    battle = defined?(SebiLinkHub) ? SebiLinkHub.current_battle : nil
    return if !battle || spectator_id == ""
    session = battle.instance_variable_get("@sebi_pvp_session") rescue nil
    return if !session || session[:remote_id].to_s != from_id.to_s
    @subscribers = {} if !@subscribers
    @subscribers[token] = { :remote_id => spectator_id, :name => spectator_name, :escaped_name => fields[2].to_s }
    publish_to(spectator_id, token, battle, "joined")
  rescue Exception
  end

  def self.handle_leave(from_id, fields)
    token = fields[0].to_s
    @subscribers.delete(token) if @subscribers
    stop_capture_helper if !@subscribers || @subscribers.length == 0
  rescue Exception
  end

  def self.forward_join_to_pvp_opponent(battle, token, spectator_id, escaped_name)
    return if !battle
    session = battle.instance_variable_get("@sebi_pvp_session") rescue nil
    return if !session || !session[:remote_id]
    SebiVisualMultiplayer.client.send_direct(session[:remote_id], "SPECTATE_JOIN", [
      token.to_s,
      spectator_id.to_s,
      escaped_name.to_s
    ])
  rescue Exception
  end

  def self.forward_leave_to_pvp_opponent(battle, token)
    return if !battle
    session = battle.instance_variable_get("@sebi_pvp_session") rescue nil
    return if !session || !session[:remote_id]
    SebiVisualMultiplayer.client.send_direct(session[:remote_id], "SPECTATE_LEAVE", [token.to_s])
  rescue Exception
  end

  def self.remove_remote(id)
    id = id.to_s
    if @subscribers
      @subscribers.delete_if { |token, entry| entry && entry[:remote_id].to_s == id }
      stop_capture_helper if @subscribers.length == 0
    end
    @views.delete(id) if @views
    return if !@watching_id || @watching_id.to_s != id
    @end_message = _INTL("El jugador observado se ha desconectado.")
    @watching_id = nil
    @watching_token = nil
    @primary_view_id = nil
    @viewer_pending = false
  rescue Exception
  end

  def self.start(battle)
    @subscribers = {} if !@subscribers
    @last_publish_frame = -9999
    @last_frame_publish_frame = -9999
    @state_sequence = 0
    @frame_sequence = 0
    @capture_session = nil if !@capture_helper_started
  rescue Exception
  end

  def self.local_view_name(battle)
    name = SebiVisualMultiplayer.local_name rescue ""
    if defined?(SebiBattleAdvisor)
      player = SebiBattleAdvisor.trainer_data(SebiBattleHistory.safe(nil) { battle.player })
      name = player["name"].to_s if player.is_a?(Hash) && player["name"].to_s != ""
    end
    return name
  rescue Exception
    return SebiVisualMultiplayer.local_name rescue _INTL("Jugador")
  end

  def self.own_party_details(battle)
    return [] if !defined?(SebiBattleAdvisor)
    party = SebiBattleHistory.safe([]) { battle.party1 }
    return SebiBattleAdvisor.party_data(party, "spectatorOwnParty")
  rescue Exception
    return []
  end

  def self.scene_sprite_data(sprite)
    return nil if !sprite
    visible = true
    begin
      visible = sprite.visible ? true : false
    rescue Exception
      visible = true
    end
    data = {
      "x" => (sprite.x.to_i rescue 0),
      "y" => (sprite.y.to_i rescue 0),
      "z" => (sprite.z.to_i rescue 0),
      "visible" => visible
    }
    data["zoomX"] = (sprite.zoom_x.to_f rescue 1.0)
    data["zoomY"] = (sprite.zoom_y.to_f rescue 1.0)
    data["width"] = (sprite.bitmap.width.to_i rescue 0)
    data["height"] = (sprite.bitmap.height.to_i rescue 0)
    return data
  rescue Exception
    return nil
  end

  def self.scene_state_for(battle)
    return {} if !defined?(SebiLinkHub)
    scene = SebiLinkHub.instance_variable_get("@battle_scene") rescue nil
    return {} if !scene || !scene.instance_variable_defined?("@sprites")
    scene_battle = scene.instance_variable_get("@battle") rescue nil
    return {} if battle && scene_battle && scene_battle != battle
    sprites = scene.instance_variable_get("@sprites") rescue nil
    return {} if !sprites
    data = {
      "graphicsWidth" => (Graphics.width rescue 512),
      "graphicsHeight" => (Graphics.height rescue 384),
      "pokemonSprites" => {},
      "boxSprites" => {},
      "baseSprites" => {}
    }
    for i in 0...4
      sprite = sprites["pokemon#{i}"] rescue nil
      info = scene_sprite_data(sprite)
      data["pokemonSprites"][i.to_s] = info if info
      box = sprites["battlebox#{i}"] rescue nil
      box_info = scene_sprite_data(box)
      data["boxSprites"][i.to_s] = box_info if box_info
    end
    ["enemybase", "playerbase"].each do |key|
      sprite = sprites[key] rescue nil
      info = scene_sprite_data(sprite)
      data["baseSprites"][key] = info if info
    end
    return data
  rescue Exception
    return {}
  end

  def self.state_for(battle, event_name)
    snapshot = nil
    if defined?(SebiBattleAdvisor)
      snapshot = SebiBattleAdvisor.battle_state(battle)
    end
    snapshot = {} if !snapshot.is_a?(Hash)
    snapshot["source"] = "Pokemon Z SebiLink Battle Spectator"
    snapshot["event"] = event_name.to_s
    snapshot["viewName"] = local_view_name(battle)
    scene_state = scene_state_for(battle)
    snapshot["scene"] = scene_state if scene_state && scene_state.length > 0
    return {
      "generatedAt" => Time.now.to_s,
      "source" => "Pokemon Z SebiLink Battle Spectator",
      "ended" => false,
      "event" => event_name.to_s,
      "turn" => SebiBattleHistory.safe(0) { battle.turncount.to_i },
      "decision" => SebiBattleHistory.safe(0) { battle.decision.to_i },
      "doubleBattle" => SebiBattleHistory.safe(false) { battle.doublebattle ? true : false },
      "pvpBattle" => SebiBattleHistory.safe(false) { battle.instance_variable_get("@sebi_pvp_session") ? true : false },
      "viewName" => local_view_name(battle),
      "ownParty" => snapshot["playerParty"] || own_party_details(battle),
      "opponentParty" => snapshot["opponentParty"] || [],
      "battleSnapshot" => snapshot
    }
  rescue Exception
    return { "generatedAt" => Time.now.to_s, "ended" => false, "event" => event_name.to_s }
  end

  def self.publish_to(remote_id, token, battle, event_name)
    state = state_for(battle, event_name)
    SebiVisualMultiplayer.client.send_direct(remote_id, "SPECTATE_STATE", [
      token.to_s,
      SebiVisualMultiplayer.client.client_id.to_s,
      SebiVisualMultiplayer.escape(local_view_name(battle)),
      SebiVisualMultiplayer.encode_object(state)
    ])
  rescue Exception
  end

  def self.publish(battle, event_name = "update")
    return if !battle
    register_pending_watches(battle)
    return if !@subscribers || @subscribers.length == 0
    for token in @subscribers.keys
      entry = @subscribers[token]
      publish_to(entry[:remote_id], token, battle, event_name) if entry
    end
    @last_publish_frame = Graphics.frame_count rescue 0
  rescue Exception
  end

  def self.publish_throttled(battle, event_name = "message")
    frame = Graphics.frame_count rescue 0
    return if frame - (@last_publish_frame || -9999) < 10
    publish(battle, event_name)
  rescue Exception
  end

  def self.finish(battle, result)
    return if !@subscribers || @subscribers.length == 0
    publish(battle, "end")
    for token in @subscribers.keys
      entry = @subscribers[token]
      remote_id = entry ? entry[:remote_id] : nil
      next if !remote_id
      SebiVisualMultiplayer.client.send_direct(remote_id, "SPECTATE_END", [
        token.to_s,
        SebiVisualMultiplayer.escape(_INTL("El combate ha terminado."))
      ])
    end
  rescue Exception
  ensure
    @subscribers = {}
    stop_capture_helper
  end

  def self.capture_helper_path
    return File.expand_path("multiplayer/battle-spectator/SebiSpectatorCapture.ps1")
  rescue Exception
    return "multiplayer/battle-spectator/SebiSpectatorCapture.ps1"
  end

  def self.quote_arg(value)
    return "\"" + value.to_s.gsub("\"", "") + "\""
  rescue Exception
    return "\"\""
  end

  def self.current_process_id
    return @current_process_id if @current_process_id && @current_process_id.to_i > 0
    return 0 if !defined?(Win32API)
    api = Win32API.new("kernel32", "GetCurrentProcessId", "", "l")
    @current_process_id = api.call.to_i
    return @current_process_id
  rescue Exception
    return 0
  end

  def self.current_window_handle
    hwnd = nil
    hwnd = pbFindRgssWindow if defined?(pbFindRgssWindow)
    if (!hwnd || hwnd.to_i == 0) && defined?(Win32API) && Win32API.respond_to?(:pbFindRgssWindow)
      hwnd = Win32API.pbFindRgssWindow
    end
    return hwnd.to_i if hwnd && hwnd.to_i != 0
    return 0
  rescue Exception
    return 0
  end

  def self.capture_session
    return @capture_session if @capture_session && @capture_session.to_s != ""
    id = SebiVisualMultiplayer.client.client_id.to_s rescue "player"
    frame = Graphics.frame_count rescue 0
    @capture_session = safe_filename(id + "_" + frame.to_s + "_" + rand(1000000).to_s)
    return @capture_session
  rescue Exception
    return "player"
  end

  def self.capture_output_path
    ensure_runtime
    return File.join(runtime_dir, "capture_" + capture_session + ".png")
  end

  def self.capture_internal_output_path
    ensure_runtime
    return File.join(runtime_dir, "capture_internal_" + capture_session + ".png")
  end

  def self.capture_stop_path
    ensure_runtime
    return File.join(runtime_dir, "capture_" + capture_session + ".stop")
  end

  def self.start_capture_helper
    @capture_helper_started = false
    return false
  rescue Exception
    @capture_helper_started = false
    return false
  end

  def self.stop_capture_helper
    return if !@capture_session
    if @capture_helper_started
      stop = capture_stop_path
      File.open(stop, "wb") { |file| file.write("stop") }
    end
  rescue Exception
  ensure
    @capture_helper_started = false
    @capture_session = nil
  end

  def self.capture_frame_data
    return nil if !@capture_helper_started
    path = capture_output_path
    return nil if !FileTest.exist?(path)
    data = nil
    File.open(path, "rb") { |file| data = file.read }
    return nil if !data || data.length == 0 || data.length > 4 * 1024 * 1024
    return [data].pack("m").gsub(/\s/, "")
  rescue Exception
    return nil
  end

  def self.capture_internal_frame_data
    return nil
  end

  def self.publish_frame(battle, force = false)
    return if !battle || !@subscribers || @subscribers.length == 0
    frame = Graphics.frame_count rescue 0
    return if !force && frame - (@last_frame_publish_frame || -9999) < 30
    @last_frame_publish_frame = frame
  rescue Exception
  end

  def self.handle_frame(from_id, fields)
    token = fields[0].to_s
    return if !@watching_token || token != @watching_token.to_s
    view_id = fields[1].to_s
    view_name = SebiVisualMultiplayer.unescape(fields[2].to_s)
    sequence = fields[3].to_i
    encoded = fields[4].to_s
    return if view_id == "" || encoded == ""
    data = encoded.unpack("m")[0]
    return if !data || data.length == 0
    path = frame_path(view_id, token)
    File.open(path, "wb") { |file| file.write(data) }
    @views = {} if !@views
    view = @views[view_id] || {}
    view[:name] = view_name
    view[:sequence] = sequence
    view[:path] = path
    @views[view_id] = view
    @viewer_pending = true
  rescue Exception
  end

  def self.network_tick
    return if (!@subscribers || @subscribers.length == 0) && (!@pending_watches || @pending_watches.length == 0)
    battle = defined?(SebiLinkHub) ? SebiLinkHub.current_battle : nil
    if battle
      register_pending_watches(battle)
      frame = Graphics.frame_count rescue 0
      publish(battle, "tick") if @subscribers && @subscribers.length > 0 &&
                                frame - (@last_publish_frame || -9999) >= 30
    end
  rescue Exception
  end

  def self.update
    return if @viewer_active
    if !@watching_token && @end_message
      message = @end_message
      @end_message = nil
      Kernel.pbMessage(message)
      return
    end
    return if !@viewer_pending || !@watching_token
    return if !@views || @views.length == 0
    has_state = false
    for view in @views.values
      has_state = true if view && view[:state].is_a?(Hash)
    end
    return if !has_state
    open_viewer
  rescue Exception
  end

  def self.view_ids
    ids = []
    return ids if !@views
    ids.push(@primary_view_id.to_s) if @primary_view_id && @views[@primary_view_id.to_s]
    for id in @views.keys
      ids.push(id.to_s) if !ids.include?(id.to_s)
    end
    return ids
  rescue Exception
    return []
  end

  def self.current_view_id(ids, index)
    return nil if !ids || ids.length == 0
    index = 0 if index < 0 || index >= ids.length
    return ids[index]
  end

  def self.load_view_bitmap(sprite, view)
    return false if !sprite || !view || !view[:path] || !FileTest.exist?(view[:path])
    sequence = view[:sequence].to_i
    return false if view[:loaded_sequence].to_i == sequence && sprite.bitmap
    bitmap = Bitmap.new(view[:path])
    old = sprite.bitmap
    sprite.bitmap = bitmap
    sprite.zoom_x = Graphics.width.to_f / bitmap.width.to_f if bitmap.width.to_i > 0
    sprite.zoom_y = Graphics.height.to_f / bitmap.height.to_f if bitmap.height.to_i > 0
    old.dispose if old && !old.disposed?
    view[:loaded_sequence] = sequence
    return true
  rescue Exception
    return false
  end

  def self.draw_overlay(sprite, ids, index)
    return if !sprite || !sprite.bitmap
    sprite.bitmap.clear
  rescue Exception
  end

  def self.draw_waiting_overlay(sprite)
    return if !sprite || !sprite.bitmap
    bitmap = sprite.bitmap
    bitmap.clear
    bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 210))
    pbSetSystemFont(bitmap) if defined?(pbSetSystemFont)
    base = Color.new(248, 248, 248)
    shadow = Color.new(0, 0, 0)
    pbDrawTextPositions(bitmap, [
      [_INTL("Esperando datos del combate..."), Graphics.width / 2, Graphics.height / 2 - 18, 2, base, shadow],
      [_INTL("B: salir"), Graphics.width / 2, Graphics.height / 2 + 10, 2, base, shadow]
    ])
  rescue Exception
  end

  def self.pokemon_detail_text(pokemon)
    return _INTL("No hay detalles disponibles.") if !pokemon
    name = pokemon["speciesName"].to_s
    name = pokemon["nickname"].to_s if name == ""
    types = pokemon["types"] || []
    stats = pokemon["stats"] || {}
    moves = pokemon["moves"] || []
    move_names = moves.collect { |move| move ? move["name"].to_s : "" }.reject { |value| value == "" }
    lines = []
    lines.push(_INTL("{1} Nv.{2}", name, pokemon["level"].to_i))
    lines.push(_INTL("Tipos: {1}", types.join(" / ")))
    lines.push(_INTL("Habilidad: {1}", pokemon["abilityName"].to_s == "" ? "-" : pokemon["abilityName"].to_s))
    lines.push(_INTL("Objeto: {1}", pokemon["itemName"].to_s == "" ? "-" : pokemon["itemName"].to_s))
    lines.push(_INTL("Stats: PS {1}, Atq {2}, Def {3}, AtqEsp {4}, DefEsp {5}, Vel {6}",
      stats["hp"].to_i, stats["attack"].to_i, stats["defense"].to_i,
      stats["spatk"].to_i, stats["spdef"].to_i, stats["speed"].to_i))
    lines.push(_INTL("Movimientos: {1}", move_names.length > 0 ? move_names.join(", ") : "-"))
    return lines.join("\n")
  rescue Exception
    return _INTL("No hay detalles disponibles.")
  end

  def self.show_details(view = nil, perspective = 0)
    if view
      show_view_party_details(view, perspective)
      return
    end
    available = []
    for id in view_ids
      view = @views[id]
      state = view ? view[:state] : nil
      party = state.is_a?(Hash) ? state["ownParty"] : nil
      next if !party || party.length == 0
      available.push([id, view[:name].to_s, party])
    end
    if available.length == 0
      Kernel.pbMessage(_INTL("Todavia no hay detalles de equipos disponibles."))
      return
    end
    commands = available.collect { |entry| entry[1].to_s == "" ? _INTL("Jugador") : entry[1].to_s }
    commands.push(_INTL("Cancelar"))
    cmd = Kernel.pbMessage(_INTL("De que jugador quieres ver detalles?"), commands, commands.length)
    return if cmd < 0 || cmd >= available.length
    party = available[cmd][2]
    pokemon_commands = []
    for pokemon in party
      pokemon_commands.push(_INTL("{1} Nv.{2}", pokemon["speciesName"].to_s, pokemon["level"].to_i))
    end
    pokemon_commands.push(_INTL("Cancelar"))
    chosen = Kernel.pbMessage(_INTL("Elige un Pokemon."), pokemon_commands, pokemon_commands.length)
    return if chosen < 0 || chosen >= party.length
    Kernel.pbMessage(pokemon_detail_text(party[chosen]))
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudieron mostrar los detalles del equipo."))
  end

  def self.show_view_party_details(view, perspective = 0)
    left_party, right_party = party_pair_for(view, perspective)
    left_label, right_label = party_labels_for(view, perspective)
    if defined?(SebiPvpPreview) && SebiPvpPreview.respond_to?(:show_readonly_teams)
      left_preview = preview_party_from_data(left_party)
      right_preview = preview_party_from_data(right_party)
      if (left_preview && left_preview.length > 0) || (right_preview && right_preview.length > 0)
        SebiPvpPreview.show_readonly_teams(_INTL("Equipo de {1}", left_label), left_preview, _INTL("Equipo de {1}", right_label), right_preview)
        return
      end
    end
    show_party_details(left_party, left_label)
  rescue Exception
    show_party_details(current_party_for(view, perspective), view ? view[:name].to_s : "")
  end

  def self.show_party_details(party, label = "")
    if !party || party.length == 0
      Kernel.pbMessage(_INTL("Todavia no hay detalles de equipos disponibles."))
      return
    end
    if defined?(SebiPvpPreview) && SebiPvpPreview.respond_to?(:show_readonly_team)
      preview_party = preview_party_from_data(party)
      if preview_party && preview_party.length > 0
        title = label.to_s == "" ? _INTL("Equipo observado") : _INTL("Equipo de {1}", label)
        SebiPvpPreview.show_readonly_team(title, preview_party)
        return
      end
    end
    commands = []
    for pokemon in party
      commands.push(_INTL("{1} Nv.{2}", pokemon_name_from_data(pokemon), pokemon["level"].to_i))
    end
    commands.push(_INTL("Cancelar"))
    title = label.to_s == "" ? _INTL("Equipo observado.") : _INTL("Equipo de {1}.", label)
    chosen = Kernel.pbMessage(title, commands, commands.length)
    return if chosen < 0 || chosen >= party.length
    Kernel.pbMessage(pokemon_detail_text(party[chosen]))
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudieron mostrar los detalles del equipo."))
  end

  def self.preview_pokemon_from_data(data)
    pokemon = display_pokemon_from_data(data)
    return nil if !pokemon
    begin
      pokemon.item = data["item"].to_i if data["item"] && pokemon.respond_to?(:item=)
    rescue Exception
    end
    begin
      if data["iv"].is_a?(Array) && pokemon.respond_to?(:iv=)
        pokemon.iv = data["iv"].collect { |value| value.to_i }
      end
    rescue Exception
    end
    begin
      if data["ev"].is_a?(Array) && pokemon.respond_to?(:ev=)
        pokemon.ev = data["ev"].collect { |value| value.to_i }
      end
    rescue Exception
    end
    begin
      moves = data["moves"]
      if moves.is_a?(Array) && defined?(PBMove)
        for i in 0...4
          move_data = moves[i] rescue nil
          move_id = move_data ? move_data["id"].to_i : 0
          pokemon.moves[i] = PBMove.new(move_id) if move_id > 0 && pokemon.moves
        end
      end
    rescue Exception
    end
    begin; pokemon.calcStats if pokemon.respond_to?(:calcStats); rescue Exception; end
    begin; pokemon.hp = data["hp"].to_i if data["hp"] && pokemon.respond_to?(:hp=); rescue Exception; end
    return pokemon
  rescue Exception
    return nil
  end

  def self.preview_party_from_data(party)
    ret = []
    return ret if !party
    for data in party
      pokemon = preview_pokemon_from_data(data)
      ret.push(pokemon) if pokemon
    end
    return ret
  rescue Exception
    return []
  end

  def self.snapshot_for_view(view)
    state = view ? view[:state] : nil
    return {} if !state.is_a?(Hash)
    snapshot = state["battleSnapshot"]
    return snapshot if snapshot.is_a?(Hash)
    return state
  rescue Exception
    return {}
  end

  def self.snapshot_battle(snapshot)
    battle = snapshot ? snapshot["battle"] : nil
    return battle if battle.is_a?(Hash)
    return {}
  rescue Exception
    return {}
  end

  def self.current_party_for(view, perspective)
    snapshot = snapshot_for_view(view)
    state = view ? view[:state] : nil
    if perspective.to_i == 0
      party = snapshot["playerParty"]
      party = state["ownParty"] if (!party || party.length == 0) && state.is_a?(Hash)
    else
      party = snapshot["opponentParty"]
      party = state["opponentParty"] if (!party || party.length == 0) && state.is_a?(Hash)
    end
    return party if party.is_a?(Array)
    return []
  rescue Exception
    return []
  end

  def self.party_pair_for(view, perspective)
    snapshot = snapshot_for_view(view)
    state = view ? view[:state] : nil
    player_party = snapshot["playerParty"]
    player_party = state["ownParty"] if (!player_party || player_party.length == 0) && state.is_a?(Hash)
    opponent_party = snapshot["opponentParty"]
    opponent_party = state["opponentParty"] if (!opponent_party || opponent_party.length == 0) && state.is_a?(Hash)
    player_party = [] if !player_party.is_a?(Array)
    opponent_party = [] if !opponent_party.is_a?(Array)
    return [opponent_party, player_party] if perspective.to_i != 0
    return [player_party, opponent_party]
  rescue Exception
    return [[], []]
  end

  def self.trainer_name_from_data(data)
    if data.is_a?(Array)
      for item in data
        name = trainer_name_from_data(item)
        return name if name.to_s != ""
      end
      return ""
    end
    return "" if !data.is_a?(Hash)
    return data["name"].to_s
  rescue Exception
    return ""
  end

  def self.opponent_label_for(snapshot)
    battle = snapshot_battle(snapshot)
    return _INTL("Salvaje") if battle && battle["trainerBattle"] == false
    name = trainer_name_from_data(snapshot ? snapshot["opponent"] : nil)
    return name if name.to_s != ""
    return _INTL("Jugador rival") if battle && battle["pvpBattle"]
    return _INTL("NPC")
  rescue Exception
    return _INTL("NPC")
  end

  def self.party_labels_for(view, perspective)
    snapshot = snapshot_for_view(view)
    player_name = (view && view[:name].to_s != "") ? view[:name].to_s : _INTL("Jugador")
    opponent_name = opponent_label_for(snapshot)
    return [opponent_name, player_name] if perspective.to_i != 0
    return [player_name, opponent_name]
  rescue Exception
    return [_INTL("Jugador"), _INTL("Rival")]
  end

  def self.pokemon_name_from_data(data)
    return "-" if !data
    name = data["nickname"].to_s
    name = data["speciesName"].to_s if name == ""
    return name == "" ? "-" : name
  rescue Exception
    return "-"
  end

  def self.battlers_for_display(snapshot, bottom, perspective)
    ret = []
    active = snapshot ? snapshot["activeBattlers"] : nil
    return ret if !active
    for battler in active
      next if !battler
      opposing = battler["isOpposing"] ? true : false
      display_bottom = perspective.to_i == 0 ? !opposing : opposing
      ret.push(battler) if display_bottom == (bottom ? true : false)
    end
    ret.sort! { |a, b| a["battlerIndex"].to_i <=> b["battlerIndex"].to_i }
    return ret
  rescue Exception
    return ret || []
  end

  def self.mirror_bitmap(path)
    @mirror_bitmaps = {} if !@mirror_bitmaps
    return @mirror_bitmaps[path].bitmap if @mirror_bitmaps[path]
    @mirror_bitmaps[path] = AnimatedBitmap.new(path)
    return @mirror_bitmaps[path].bitmap
  rescue Exception
    return nil
  end

  def self.picture_bitmap(name)
    return mirror_bitmap("Graphics/Pictures/" + name.to_s)
  rescue Exception
    return nil
  end

  def self.draw_mirror_text(bitmap, text, x, y, align = 0, base = nil, shadow = nil)
    return if !bitmap
    pbSetSystemFont(bitmap) if defined?(pbSetSystemFont)
    base = Color.new(248, 248, 248) if !base
    shadow = Color.new(32, 32, 40) if !shadow
    pbDrawTextPositions(bitmap, [[text.to_s, x, y, align, base, shadow]])
  rescue Exception
  end

  def self.draw_mirror_text_sized(bitmap, text, x, y, align = 0, size = 14, base = nil, shadow = nil)
    return if !bitmap
    pbSetSystemFont(bitmap) if defined?(pbSetSystemFont)
    old_size = bitmap.font.size rescue nil
    bitmap.font.size = size.to_i if bitmap.respond_to?(:font) && bitmap.font
    base = Color.new(248, 248, 248) if !base
    shadow = Color.new(32, 32, 40) if !shadow
    pbDrawTextPositions(bitmap, [[text.to_s, x, y, align, base, shadow]])
    bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
  rescue Exception
    begin
      bitmap.font.size = old_size if old_size && bitmap.respond_to?(:font) && bitmap.font
    rescue Exception
    end
  end

  def self.mirror_fit_text(bitmap, text, max_width)
    value = text.to_s
    return value if !bitmap || max_width.to_i <= 0
    return value if (bitmap.text_size(value).width rescue 0) <= max_width.to_i
    suffix = "..."
    while value.length > 1 && (bitmap.text_size(value + suffix).width rescue 9999) > max_width.to_i
      value = value[0, value.length - 1]
    end
    return value + suffix
  rescue Exception
    return text.to_s
  end

  def self.scene_info(snapshot, group, key)
    scene = snapshot ? snapshot["scene"] : nil
    return nil if !scene.is_a?(Hash)
    values = scene[group]
    return nil if !values.is_a?(Hash)
    return values[key.to_s] || values[key.to_i]
  rescue Exception
    return nil
  end

  def self.draw_mirror_background(bitmap, snapshot = nil, perspective = 0)
    return if !bitmap
    bg = mirror_bitmap("Graphics/Battlebacks/battlebgPradera")
    if bg
      bitmap.stretch_blt(Rect.new(0, 0, Graphics.width, Graphics.height), bg, Rect.new(0, 0, bg.width, bg.height))
    else
      bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(96, 168, 136))
      bitmap.fill_rect(0, 0, Graphics.width, 120, Color.new(116, 188, 220))
      bitmap.fill_rect(0, 120, Graphics.width, Graphics.height - 120, Color.new(96, 168, 112))
    end
    playerbase = mirror_bitmap("Graphics/Battlebacks/playerbasePradera")
    enemybase = mirror_bitmap("Graphics/Battlebacks/enemybasePradera")
    enemy_info = scene_info(snapshot, "baseSprites", "enemybase")
    player_info = scene_info(snapshot, "baseSprites", "playerbase")
    if enemybase
      ex = enemy_info ? enemy_info["x"].to_i : Graphics.width - 272
      ey = enemy_info ? enemy_info["y"].to_i : 94
      bitmap.blt(ex, ey, enemybase, Rect.new(0, 0, enemybase.width, enemybase.height))
    else
      bitmap.fill_rect(Graphics.width - 252, 112, 178, 28, Color.new(72, 144, 88))
    end
    if playerbase
      px = player_info ? player_info["x"].to_i : -84
      py = player_info ? player_info["y"].to_i : 176
      bitmap.blt(px, py, playerbase, Rect.new(0, 0, playerbase.width, playerbase.height))
    else
      bitmap.fill_rect(36, Graphics.height - 170, 230, 34, Color.new(72, 144, 88))
    end
  rescue Exception
  end

  def self.draw_hp_bar_on(bitmap, x, y, width, hp, total)
    total = total.to_i
    hp = hp.to_i
    total = 1 if total <= 0
    hp = 0 if hp < 0
    hp = total if hp > total
    fill = hp * width / total
    color = Color.new(96, 248, 96)
    color = Color.new(248, 216, 0) if hp <= total / 2
    color = Color.new(248, 72, 56) if hp <= total / 4
    bitmap.fill_rect(x, y, width + 2, 8, Color.new(32, 32, 32))
    bitmap.fill_rect(x + 1, y + 1, width, 6, Color.new(232, 240, 232))
    bitmap.fill_rect(x + 1, y + 1, fill, 6, color)
  rescue Exception
  end

  def self.gender_symbol_from_data(data)
    gender = data ? data["gender"].to_i : 2
    return ["\342\231\202", Color.new(72, 168, 248)] if gender == 0
    return ["\342\231\200", Color.new(248, 96, 136)] if gender == 1
    return ["", Color.new(248, 248, 248)]
  rescue Exception
    return ["", Color.new(248, 248, 248)]
  end

  def self.draw_spectator_type_icon(bitmap, sheet, type, x, y, width = 14, height = 16)
    return if !bitmap || !sheet || type.to_i < 0
    bitmap.stretch_blt(Rect.new(x.to_i, y.to_i, width.to_i, height.to_i), sheet, Rect.new(0, type.to_i * 28, 24, 28))
  rescue Exception
  end

  def self.draw_spectator_type_badges(bitmap, data, x, y)
    sheet = picture_bitmap("types_ico")
    return if !sheet || !data
    ids = []
    type1 = data["type1"].to_i rescue -1
    type2 = data["type2"].to_i rescue type1
    ids.push(type1) if type1 >= 0
    ids.push(type2) if type2 >= 0 && type2 != type1
    for i in 0...ids.length
      draw_spectator_type_icon(bitmap, sheet, ids[i], x + i * 19, y, 17, 19)
    end
  rescue Exception
  end

  def self.spectator_weakness_types(data)
    return [] if !data || !defined?(PBTypes)
    type1 = data["type1"].to_i rescue -1
    type2 = data["type2"].to_i rescue type1
    type3 = -1
    begin
      effects = data["effects"]
      type3 = effects["Type3"].to_i if effects && effects["Type3"]
    rescue Exception
      type3 = -1
    end
    return SebiBattleWeaknessOverlay.weakness_types_for_types(type1, type2, type3) if defined?(SebiBattleWeaknessOverlay)
    return []
  rescue Exception
    return []
  end

  def self.draw_spectator_weakness_icons(bitmap, data, x, y, align_right = false)
    return if !defined?(SebiBattleWeaknessOverlay) || !SebiBattleWeaknessOverlay.visible?
    sheet = picture_bitmap("types_ico")
    return if !sheet
    types = spectator_weakness_types(data)
    count = types.length
    icon_w = 17
    icon_h = 19
    spacing = 18
    start_x = align_right ? x - count * spacing : x
    for i in 0...count
      draw_spectator_type_icon(bitmap, sheet, types[i][0], start_x + i * spacing, y, icon_w, icon_h)
    end
  rescue Exception
  end

  def self.draw_status_icon(bitmap, data, x, y)
    status = data ? data["status"].to_i : 0
    return if status <= 0
    sheet = picture_bitmap("battleStatuses")
    return if !sheet
    row = status - 1
    row = 0 if row < 0
    bitmap.stretch_blt(Rect.new(x.to_i, y.to_i, 28, 10), sheet, Rect.new(0, row * 16, 44, 16))
  rescue Exception
  end

  def self.box_text_base
    return PokeBattle_SceneConstants::BOXTEXTBASECOLOR if defined?(PokeBattle_SceneConstants)
    return Color.new(255, 255, 255)
  rescue Exception
    return Color.new(255, 255, 255)
  end

  def self.box_text_shadow
    return PokeBattle_SceneConstants::BOXTEXTSHADOWCOLOR if defined?(PokeBattle_SceneConstants)
    return Color.new(45, 45, 45)
  rescue Exception
    return Color.new(45, 45, 45)
  end

  def self.box_sprite_base_x(bottom)
    return bottom ? 34 : 16
  rescue Exception
    return bottom ? 34 : 16
  end

  def self.draw_databox(bitmap, data, bottom, order, snapshot = nil, perspective = 0)
    return if !bitmap || !data
    double = snapshot_battle(snapshot)["doubleBattle"] ? true : false
    box_name = bottom ? (double ? "battlePlayerBoxD" : "battlePlayerBoxS") : (double ? "battleFoeBoxD" : "battleFoeBoxS")
    box_bitmap = picture_bitmap(box_name)
    width = box_bitmap ? box_bitmap.width : 260
    height = box_bitmap ? box_bitmap.height : (bottom ? 86 : 62)
    scene_key = visual_scene_key(bottom, order, double, data, perspective)
    info = scene_info(snapshot, "boxSprites", scene_key)
    x = info ? info["x"].to_i : (bottom ? (Graphics.width - width) : 0)
    y = info ? info["y"].to_i : (bottom ? (Graphics.height - 182 + order.to_i * 54) : (46 + order.to_i * 48))
    if box_bitmap
      bitmap.blt(x, y, box_bitmap, Rect.new(0, 0, box_bitmap.width, box_bitmap.height))
    else
      bitmap.fill_rect(x, y, width, height, Color.new(32, 48, 56))
      bitmap.fill_rect(x + 2, y + 2, width - 4, height - 4, Color.new(232, 238, 238))
    end
    name = pokemon_name_from_data(data)
    name = name[0, 15] + "..." if name.length > 18
    sprite_base_x = box_sprite_base_x(bottom)
    text_base = box_text_base
    text_shadow = box_text_shadow
    name_x = x + sprite_base_x + 8
    name_y = y + 6
    name = mirror_fit_text(bitmap, name, bottom ? 142 : 130)
    draw_mirror_text(bitmap, name, name_x, name_y, 0, text_base, text_shadow)
    gender, gender_color = gender_symbol_from_data(data)
    gender_x = name_x + (bitmap.text_size(name).width rescue (name.length * 8)) + 6
    draw_mirror_text(bitmap, gender, gender_x, name_y, 0, gender_color, text_shadow) if gender != ""
    draw_mirror_text(bitmap, _INTL("Nv.{1}", data["level"].to_i), x + sprite_base_x + 202, y + 8, 1, text_base, text_shadow)
    draw_spectator_type_badges(bitmap, data, name_x, y + 30)
    hp_x = x + sprite_base_x + 102
    hp_y = y + 40
    draw_hp_bar_on(bitmap, hp_x, hp_y, 96, data["hp"].to_i, data["totalhp"].to_i)
    if bottom
      hp_text = _INTL("{1}/{2}", data["hp"].to_i, data["totalhp"].to_i)
      draw_mirror_text_sized(bitmap, hp_text, x + sprite_base_x + 188, y + 48, 1, 16, text_base, text_shadow)
    end
    draw_status_icon(bitmap, data, x + sprite_base_x + 24, y + 36)
    weakness_x = bottom ? x + width - 12 : x + sprite_base_x + 8
    weakness_y = y - 11
    draw_spectator_weakness_icons(bitmap, data, weakness_x, weakness_y, bottom)
  rescue Exception
  end

  def self.draw_command_panel(bitmap, view, perspective, ids, index, command_index = 2)
    y = Graphics.height - 96
    bg = picture_bitmap("battleCommand")
    if bg
      bitmap.blt(0, y, bg, Rect.new(0, 0, bg.width, bg.height))
    else
      bitmap.fill_rect(0, y, Graphics.width, 96, Color.new(40, 68, 72))
      bitmap.fill_rect(6, y + 6, Graphics.width - 210, 84, Color.new(68, 84, 104))
    end
    bitmap.fill_rect(0, y, Graphics.width, 96, Color.new(0, 0, 0, 120))
    left_width = Graphics.width - 282
    draw_mirror_text(bitmap, _INTL("Modo espectador"), 18, y + 10, 0)
    draw_mirror_text(bitmap, _INTL("L/R: Cambiar bando"), 18, y + 38, 0)
    buttons = picture_bitmap("battleCommandButtons")
    rows = [0, 2, 1, 3]
    for i in 0...4
      bx = Graphics.width - 260 + (i % 2) * 130
      by = y + 4 + (i / 2) * 46
      if buttons
        sx = i == command_index.to_i ? 130 : 0
        bitmap.blt(bx, by, buttons, Rect.new(sx, rows[i] * 46, 130, 46))
      else
        bitmap.fill_rect(bx, by, 126, 42, i == command_index.to_i ? Color.new(248, 216, 72) : Color.new(28, 36, 44))
      end
    end
    snapshot = snapshot_for_view(view)
    battle = snapshot_battle(snapshot)
    turn = battle["turn"].to_i
    labels = party_labels_for(view, perspective)
    turn_text = mirror_fit_text(bitmap, _INTL("Turno {1} - {2}", turn, labels[0].to_s), left_width)
    draw_mirror_text(bitmap, turn_text, 18, y + 66, 0)
  rescue Exception
  end

  def self.display_position(bottom, order, double, data = nil, snapshot = nil, perspective = 0)
    if data
      info = scene_info(snapshot, "pokemonSprites", visual_scene_key(bottom, order, double, data, perspective))
      return [info["x"].to_i, info["y"].to_i] if info && info["visible"] != false
    end
    if !double
      return bottom ? [130, 278] : [386, 148]
    end
    if bottom
      return order.to_i == 0 ? [102, 278] : [188, 258]
    end
    return order.to_i == 0 ? [354, 134] : [430, 154]
  rescue Exception
    return bottom ? [130, 278] : [386, 148]
  end

  def self.display_position_legacy(bottom, order, double)
    if defined?(PokeBattle_SceneConstants)
      if bottom
        if double
          return [PokeBattle_SceneConstants::PLAYERBATTLERD1_X, PokeBattle_SceneConstants::PLAYERBATTLERD1_Y] if order.to_i == 0
          return [PokeBattle_SceneConstants::PLAYERBATTLERD2_X, PokeBattle_SceneConstants::PLAYERBATTLERD2_Y]
        end
        return [PokeBattle_SceneConstants::PLAYERBATTLER_X, PokeBattle_SceneConstants::PLAYERBATTLER_Y]
      else
        if double
          return [PokeBattle_SceneConstants::FOEBATTLERD1_X, PokeBattle_SceneConstants::FOEBATTLERD1_Y] if order.to_i == 0
          return [PokeBattle_SceneConstants::FOEBATTLERD2_X, PokeBattle_SceneConstants::FOEBATTLERD2_Y]
        end
        return [PokeBattle_SceneConstants::FOEBATTLER_X, PokeBattle_SceneConstants::FOEBATTLER_Y]
      end
    end
    return bottom ? [128 + order.to_i * 74, Graphics.height - 120 + order.to_i * 12] : [Graphics.width - 128 - order.to_i * 74, 118 - order.to_i * 12]
  rescue Exception
    return bottom ? [128, Graphics.height - 120] : [Graphics.width - 128, 118]
  end

  def self.display_pokemon_from_data(data)
    return nil if !defined?(PokeBattle_Pokemon) || !data
    species = data["species"].to_i
    return nil if species <= 0
    level = data["level"].to_i
    level = 1 if level <= 0
    pokemon = PokeBattle_Pokemon.new(species, level)
    begin; pokemon.form = data["form"].to_i if pokemon.respond_to?(:form=); rescue Exception; end
    begin; pokemon.name = pokemon_name_from_data(data) if pokemon.respond_to?(:name=); rescue Exception; end
    begin; pokemon.instance_variable_set("@gender", data["gender"].to_i); rescue Exception; end
    begin
      if data.has_key?("shiny")
        if data["shiny"]
          pokemon.makeShiny if pokemon.respond_to?(:makeShiny)
          pokemon.shinyflag = true if pokemon.respond_to?(:shinyflag=)
        else
          pokemon.makeNotShiny if pokemon.respond_to?(:makeNotShiny)
          pokemon.shinyflag = false if pokemon.respond_to?(:shinyflag=)
        end
      end
    rescue Exception
    end
    return pokemon
  rescue Exception
    return nil
  end

  def self.sprite_signature(data, bottom)
    return "" if !data
    return [data["species"].to_i, data["form"].to_i, data["gender"].to_i, data["shiny"] ? 1 : 0, bottom ? 1 : 0].join("|")
  rescue Exception
    return ""
  end

  def self.visual_battler_index(bottom, order, double)
    return bottom ? 0 : 1 if !double
    if bottom
      return order.to_i == 0 ? 0 : 2
    end
    return order.to_i == 0 ? 1 : 3
  rescue Exception
    return bottom ? 0 : 1
  end

  def self.visual_scene_key(bottom, order, double, data = nil, perspective = 0)
    return data["battlerIndex"].to_i if perspective.to_i == 0 && data
    return visual_battler_index(bottom, order, double)
  rescue Exception
    return bottom ? 0 : 1
  end

  def self.update_mirror_sprites(sprites, viewport, snapshot, perspective)
    sprites = {} if !sprites
    battle = snapshot_battle(snapshot)
    double = battle["doubleBattle"] ? true : false
    wanted = {}
    [["top", false], ["bottom", true]].each do |entry|
      side_name = entry[0]
      bottom = entry[1]
      battlers = battlers_for_display(snapshot, bottom, perspective)
      for i in 0...battlers.length
        data = battlers[i]
        key = side_name + "_" + data["battlerIndex"].to_i.to_s
        wanted[key] = true
        signature = sprite_signature(data, bottom)
        sprite_info = sprites[key]
        if !sprite_info || sprite_info[:signature] != signature
          begin
            sprite_info[:sprite].dispose if sprite_info && sprite_info[:sprite] && !sprite_info[:sprite].disposed?
          rescue Exception
          end
          sprite = nil
          if defined?(PokemonBattlerSprite)
            sprite_index = visual_scene_key(bottom, i, double, data, perspective)
            sprite = PokemonBattlerSprite.new(double, sprite_index, viewport)
            pokemon = display_pokemon_from_data(data)
            sprite.setPokemonBitmap(pokemon, bottom) if pokemon
            sprite.visible = true
            sprite.z = bottom ? 30 + i : 20 + i
          end
          sprite_info = { :sprite => sprite, :signature => signature }
          sprites[key] = sprite_info
        end
        sprite = sprite_info[:sprite]
        if sprite
          x, y = display_position(bottom, i, double, data, snapshot, perspective)
          sprite.x = x
          sprite.y = y
          scene_pos = scene_info(snapshot, "pokemonSprites", visual_scene_key(bottom, i, double, data, perspective))
          if scene_pos
            begin; sprite.zoom_x = scene_pos["zoomX"].to_f if sprite.respond_to?(:zoom_x=); rescue Exception; end
            begin; sprite.zoom_y = scene_pos["zoomY"].to_f if sprite.respond_to?(:zoom_y=); rescue Exception; end
          end
          sprite.visible = true
          sprite.update if sprite.respond_to?(:update)
        end
      end
    end
    for key in sprites.keys
      next if wanted[key]
      begin
        sprites[key][:sprite].dispose if sprites[key] && sprites[key][:sprite] && !sprites[key][:sprite].disposed?
      rescue Exception
      end
      sprites.delete(key)
    end
    return sprites
  rescue Exception
    return sprites || {}
  end

  def self.draw_mirror_view(canvas, view, ids, index, perspective, command_index = 2)
    return if !canvas || !canvas.bitmap
    bitmap = canvas.bitmap
    bitmap.clear
    snapshot = snapshot_for_view(view)
    draw_mirror_background(bitmap, snapshot, perspective)
    top = battlers_for_display(snapshot, false, perspective)
    bottom = battlers_for_display(snapshot, true, perspective)
    for i in 0...top.length
      draw_databox(bitmap, top[i], false, i, snapshot, perspective)
    end
    for i in 0...bottom.length
      draw_databox(bitmap, bottom[i], true, i, snapshot, perspective)
    end
    draw_command_panel(bitmap, view, perspective, ids, index, command_index)
  rescue Exception
  end

  def self.open_viewer
    @viewer_active = true
    @viewer_pending = false
    ids = view_ids
    index = 0
    perspective = 0
    viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    viewport.z = 99990
    canvas = BitmapSprite.new(Graphics.width, Graphics.height, viewport)
    canvas.z = 0
    pokemon_sprites = {}
    loaded_key = nil
    waiting_drawn = false
    command_index = 2
    loop do
      break if !@watching_token
      ids = view_ids
      if ids.length == 0
        if !waiting_drawn
          draw_waiting_overlay(canvas)
          waiting_drawn = true
        end
      else
        index = 0 if index >= ids.length
        id = current_view_id(ids, index)
        view = @views[id]
        sequence = view ? view[:sequence].to_i : 0
        key = id.to_s + "|" + sequence.to_s + "|" + perspective.to_s + "|" + ids.length.to_s + "|" + command_index.to_s
        if view && view[:state].is_a?(Hash) && loaded_key != key
          loaded_key = key
          waiting_drawn = false
          draw_mirror_view(canvas, view, ids, index, perspective, command_index)
          pokemon_sprites = update_mirror_sprites(pokemon_sprites, viewport, snapshot_for_view(view), perspective)
        elsif (!view || !view[:state].is_a?(Hash)) && !waiting_drawn
          draw_waiting_overlay(canvas)
          waiting_drawn = true
        else
          for info in pokemon_sprites.values
            sprite = info ? info[:sprite] : nil
            sprite.update if sprite && sprite.respond_to?(:update)
          end
        end
      end
      Graphics.update
      Input.update
      SebiVisualMultiplayer.global_tick if defined?(SebiVisualMultiplayer)
      if defined?(SebiExtraControls) && SebiExtraControls.weakness_trigger?
        SebiBattleWeaknessOverlay.toggle(nil) if defined?(SebiBattleWeaknessOverlay)
        loaded_key = nil
      elsif ids.length > 0 && (Input.trigger?(Input::L) || Input.trigger?(Input::LEFT))
        if Input.trigger?(Input::LEFT)
          command_index = (command_index % 2 == 0) ? command_index + 1 : command_index - 1
        elsif ids.length > 1
          index = (index - 1) % ids.length
        else
          perspective = 1 - perspective
        end
        loaded_key = nil
      elsif ids.length > 0 && (Input.trigger?(Input::R) || Input.trigger?(Input::RIGHT))
        if Input.trigger?(Input::RIGHT)
          command_index = (command_index % 2 == 0) ? command_index + 1 : command_index - 1
        elsif ids.length > 1
          index = (index + 1) % ids.length
        else
          perspective = 1 - perspective
        end
        loaded_key = nil
      elsif ids.length > 0 && Input.trigger?(Input::UP)
        command_index = command_index >= 2 ? command_index - 2 : command_index + 2
        loaded_key = nil
      elsif ids.length > 0 && Input.trigger?(Input::DOWN)
        command_index = command_index < 2 ? command_index + 2 : command_index - 2
        loaded_key = nil
      elsif defined?(SebiControls) ? SebiControls.button_x_trigger? : Input.trigger?(Input::X)
        id = current_view_id(ids, index)
        show_details(@views[id], perspective) if id && @views
        loaded_key = nil
      elsif (defined?(SebiControls) ? SebiControls.button_a_trigger? : Input.trigger?(Input::C)) || Input.trigger?(Input::C)
        if command_index == 2
          id = current_view_id(ids, index)
          show_details(@views[id], perspective) if id && @views
          loaded_key = nil
        elsif command_index == 3
          stop_watching(false)
          Input.update
          break
        end
      elsif defined?(SebiControls) ? SebiControls.button_b_trigger? : Input.trigger?(Input::B)
        stop_watching(false)
        Input.update
        break
      end
    end
  rescue Exception
    SebiVisualMultiplayer.log("spectator viewer failed: " + $!.class.to_s + ": " + $!.message.to_s) if defined?(SebiVisualMultiplayer)
  ensure
    begin
      if pokemon_sprites
        for info in pokemon_sprites.values
          sprite = info ? info[:sprite] : nil
          sprite.dispose if sprite && !sprite.disposed?
        end
      end
      canvas.bitmap.dispose if canvas && canvas.bitmap && !canvas.bitmap.disposed?
      canvas.dispose if canvas && !canvas.disposed?
      viewport.dispose if viewport && !viewport.disposed?
    rescue Exception
    end
    @viewer_active = false
    message = @end_message
    @end_message = nil
    Kernel.pbMessage(message) if message && message.to_s != ""
  end
end

module SebiLinkHub
  HUB_KEY = 0x7B
  COOLDOWN_FRAMES = 20
  COMMAND_POLL_FRAMES = 15
  @last_open_frame = 0
  @last_command_poll_frame = -9999
  @open = false
  @hub_key_pressed = false
  @get_async_key_state = nil
  @battle_scene = nil
  @processing_command = false

  def self.hub_path
    return File.expand_path("multiplayer/sebilink-hub/SebiLinkHub.ps1")
  rescue Exception
    return "multiplayer/sebilink-hub/SebiLinkHub.ps1"
  end

  def self.runtime_dir
    return SebiLinkPaths.runtime_dir("sebilink-hub") if defined?(SebiLinkPaths)
    return File.expand_path("multiplayer/sebilink-hub/runtime")
  rescue Exception
    return "SebiLinkConfig/sebilink-hub/runtime"
  end

  def self.command_path
    return File.join(runtime_dir, "commands.txt")
  end

  def self.result_path
    return File.join(runtime_dir, "last_result.json")
  end

  def self.ensure_dir(path)
    path = path.to_s.gsub("\\", "/")
    parts = path.split("/")
    current = ""
    for part in parts
      next if part == ""
      if current == ""
        current = part
      else
        current += "/" + part
      end
      next if part =~ /\A[A-Za-z]:\z/
      Dir.mkdir(current) if !FileTest.directory?(current)
    end
  rescue Exception
  end

  def self.atomic_write(path, text)
    if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:atomic_write)
      SebiSaveEditor.atomic_write(path, text)
      return
    end
    ensure_dir(File.dirname(path))
    File.open(path, "wb") { |file| file.write(text.to_s) }
  rescue Exception
  end

  def self.json(value)
    return SebiSaveEditor.json(value) if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:json)
    text = value.to_s
    text = text.gsub(/\\/) { "\\\\" }
    text = text.gsub(/"/) { "\\\"" }
    text = text.gsub(/\r/) { "\\r" }
    text = text.gsub(/\n/) { "\\n" }
    text = text.gsub(/\t/) { "\\t" }
    return "\"" + text + "\""
  rescue Exception
    return "\"\""
  end

  def self.write_result(seq, ok, message)
    atomic_write(result_path, json({
      "seq" => seq.to_s,
      "ok" => ok ? true : false,
      "message" => message.to_s,
      "frame" => (Graphics.frame_count rescue 0),
      "time" => Time.now.to_s
    }))
  rescue Exception
  end

  def self.delete_runtime_file(path)
    begin
      File.delete(path) if path && FileTest.exist?(path)
    rescue Exception
    end
  end

  def self.reset_for_save_change
    @open = false
    @processing_command = false
    delete_runtime_file(command_path)
    delete_runtime_file(result_path)
  rescue Exception
  end

  def self.percent_decode(value)
    return SebiSaveEditor.percent_decode(value) if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:percent_decode)
    value = value.to_s.gsub("+", " ")
    return value.gsub(/%([0-9A-Fa-f]{2})/) { $1.to_i(16).chr }
  rescue Exception
    return value.to_s
  end

  def self.parse_command(line)
    return SebiSaveEditor.parse_command(line) if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:parse_command)
    parts = line.to_s.gsub(/\r|\n/, "").split("|")
    ret = { "seq" => parts[0].to_s, "cmd" => parts[1].to_s, "args" => {} }
    for i in 2...parts.length
      pair = parts[i].split("=", 2)
      next if pair.length < 2
      ret["args"][pair[0].to_s] = percent_decode(pair[1].to_s)
    end
    return ret
  rescue Exception
    return nil
  end

  def self.battle_scene=(scene)
    @battle_scene = scene
  rescue Exception
  end

  def self.scene_battle
    return nil if !@battle_scene
    battle = @battle_scene.instance_variable_get("@battle") rescue nil
    return nil if !battle
    return battle if battle.respond_to?(:battlers)
    return nil
  rescue Exception
    return nil
  end

  def self.find_live_battle
    return @battle_search_result if @battle_search_frame &&
                                    (Graphics.frame_count rescue 0) - @battle_search_frame.to_i < 15
    @battle_search_frame = Graphics.frame_count rescue 0
    @battle_search_result = nil
    return nil if !defined?(PokeBattle_Battle)
    ObjectSpace.each_object(PokeBattle_Battle) do |battle|
      next if !battle || !battle.respond_to?(:battlers)
      begin
        next if battle.decision.to_i != 0
      rescue Exception
      end
      battlers = battle.battlers rescue nil
      next if !battlers || battlers.length == 0
      @battle_search_result = battle
      break
    end
    return @battle_search_result
  rescue Exception
    @battle_search_result = nil
    return nil
  end

  def self.current_battle
    battle = scene_battle
    return battle if battle
    battle = find_live_battle
    return battle if battle
    return nil if !in_battle?
    return nil
  rescue Exception
    return nil
  end

  def self.quote_arg(value)
    return "\"" + value.to_s.gsub("\"", "") + "\""
  rescue Exception
    return "\"\""
  end

  def self.open_powershell_script(path, extra_params = nil)
    if defined?(SebiSaveEditor) && SebiSaveEditor.respond_to?(:open_path)
      return SebiSaveEditor.open_path(path) if !extra_params || extra_params.to_s == ""
    end
    params = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " + quote_arg(path)
    params += " " + extra_params.to_s if extra_params && extra_params.to_s != ""
    if defined?(Win32API)
      shell = Win32API.new("shell32", "ShellExecuteA", "LPPPPI", "I")
      result = shell.call(0, "open", "powershell.exe", params, nil, 0)
      return true if result && result.to_i > 32
    end
    system("cmd /c start \"\" powershell.exe " + params)
    return true
  rescue Exception
    return false
  end

  def self.open_window(open_ai = false)
    path = hub_path
    if !FileTest.exist?(path)
      Kernel.pbMessage(_INTL("No se encontro la ventana SebiLink Hub."))
      return false
    end
    extra_params = open_ai ? "-OpenAi" : nil
    if !open_powershell_script(path, extra_params)
      Kernel.pbMessage(_INTL("No se pudo abrir la ventana SebiLink Hub."))
      return false
    end
    return true
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir la ventana SebiLink Hub.")) rescue nil
    return false
  end

  def self.db_key_name
    return SebiExtraControls.db_key_name if defined?(SebiExtraControls)
    return "F3"
  rescue Exception
    return "F3"
  end

  def self.weakness_key_name
    return SebiExtraControls.weakness_key_name if defined?(SebiExtraControls)
    return "F4"
  rescue Exception
    return "F4"
  end

  def self.level_key_name
    return SebiExtraControls.level_key_name if defined?(SebiExtraControls)
    return "F6"
  rescue Exception
    return "F6"
  end

  def self.in_battle?
    return true if scene_battle
    return ($game_temp && $game_temp.in_battle) ? true : false
  rescue Exception
    return false
  end

  def self.safe_to_open?
    return false if @open
    return false if !$Trainer
    if $game_temp
      return false if $game_temp.battle_calling
      return false if $game_temp.message_window_showing
      return false if $game_temp.player_transferring
    end
    begin
      return false if !in_battle? && pbMapInterpreterRunning?
    rescue Exception
    end
    return true
  rescue Exception
    return false
  end

  def self.raw_key_pressed?(key)
    begin
      if defined?(SebiControls) && SebiControls.respond_to?(:raw_key_press?)
        return SebiControls.raw_key_press?(key)
      end
      @get_async_key_state = Win32API.new("user32", "GetAsyncKeyState", "i", "i") if !@get_async_key_state && defined?(Win32API)
      return false if !@get_async_key_state
      return (@get_async_key_state.call(key.to_i) & 0x8000) != 0
    rescue Exception
      return false
    end
  end

  def self.hub_key_triggered?
    triggered = false
    begin
      triggered = true if defined?(Input) && Input.respond_to?(:triggerex?) && Input.triggerex?(HUB_KEY)
    rescue Exception
    end
    pressed = raw_key_pressed?(HUB_KEY)
    triggered = true if pressed && !@hub_key_pressed
    @hub_key_pressed = pressed
    return triggered
  rescue Exception
    @hub_key_pressed = false
    return false
  end

  def self.handle_shortcut
    return if !hub_key_triggered?
    frame = Graphics.frame_count rescue 0
    return if @last_open_frame && frame - @last_open_frame < COOLDOWN_FRAMES
    @last_open_frame = frame
    open_window
  rescue Exception
  end

  def self.safe_to_run_menu_action?
    return safe_to_open?
  rescue Exception
    return false
  end

  def self.run_menu_action(message = "Accion ejecutada.")
    return [false, _INTL("No se puede abrir esa opcion ahora mismo. Cierra mensajes, transiciones o eventos en curso.")] if !safe_to_run_menu_action?
    yield
    return [true, message]
  rescue Exception
    return [false, _INTL("No se pudo ejecutar la accion F12: {1}", $!.message.to_s)]
  end

  def self.open_original_controls
    return run_menu_action(_INTL("Controles originales abiertos.")) do
      if defined?(PokemonControlsScene) && defined?(PokemonControls)
        pbFadeOutIn(99999) do
          scene = PokemonControlsScene.new
          screen = PokemonControls.new(scene)
          screen.pbStartScreen
        end
      else
        Kernel.pbMessage(_INTL("La pantalla de controles original no esta disponible."))
      end
    end
  end

  def self.open_pokemondb_context
    if defined?(SebiPokemonDB)
      battle = current_battle
      if battle
        return [SebiPokemonDB.open_pending_or_first_opponent(battle), _INTL("PokemonDB solicitado para el combate.")]
      end
      return run_menu_action(_INTL("PokemonDB solicitado para el equipo.")) do
        if $Trainer && $Trainer.party
          SebiPokemonDB.open_team($Trainer.party)
        else
          Kernel.pbMessage(_INTL("No hay equipo cargado para abrir PokemonDB."))
        end
      end
    end
    return [false, _INTL("PokemonDB no esta disponible.")]
  rescue Exception
    return [false, _INTL("No se pudo abrir PokemonDB.")]
  end

  def self.toggle_weakness_overlay
    if in_battle? && @battle_scene && defined?(SebiBattleWeaknessOverlay)
      SebiBattleWeaknessOverlay.toggle(@battle_scene)
      return [true, _INTL("Debilidades de combate alternadas.")]
    end
    return [false, _INTL("Las debilidades solo se pueden alternar durante un combate.")]
  rescue Exception
    return [false, _INTL("No se pudo alternar debilidades.")]
  end

  def self.use_registered_item
    return [false, _INTL("El objeto registrado solo se puede usar en el mapa.")] if in_battle?
    return run_menu_action(_INTL("Objeto registrado solicitado.")) do
      if $PokemonTemp
        $PokemonTemp.keyItemCalling = true
      else
        Kernel.pbMessage(_INTL("No hay objeto registrado disponible ahora."))
      end
    end
  rescue Exception
    return [false, _INTL("No se pudo usar el objeto registrado.")]
  end

  def self.run_action(action, args = nil)
    args ||= {}
    case action.to_s
    when "open_original_controls"
      return open_original_controls
    when "open_pokemondb_context"
      return open_pokemondb_context
    when "toggle_weakness_overlay"
      return toggle_weakness_overlay
    when "open_battle_advisor"
      if !in_battle?
        return [false, _INTL("El consejo IA solo se puede pedir durante un combate.")]
      end
      if defined?(SebiBattleAdvisor)
        return [SebiBattleAdvisor.write_state(current_battle), _INTL("Combate exportado para la IA del hub F12.")]
      end
      return [false, _INTL("Consejo IA no disponible.")]
    when "export_battle_advisor_state"
      if !in_battle?
        return [false, _INTL("El consejo IA solo se puede pedir durante un combate.")]
      end
      if defined?(SebiBattleAdvisor)
        return [SebiBattleAdvisor.write_state(current_battle), _INTL("Combate exportado para la IA.")]
      end
      return [false, _INTL("Consejo IA no disponible.")]
    when "export_ai_team_state"
      if defined?(SebiBattleAdvisor)
        return [SebiBattleAdvisor.write_team_state, _INTL("Equipo y cajas exportados para la IA.")]
      end
      return [false, _INTL("IA de equipo no disponible.")]
    when "use_registered_item"
      return use_registered_item
    when "equalize_party"
      return run_menu_action(_INTL("Igualar niveles solicitado.")) { SebiCheats.equalize_party_levels if defined?(SebiCheats) }
    when "open_save_editor"
      if defined?(SebiSaveEditor)
        SebiSaveEditor.open_editor
        return [true, _INTL("Editor F7 solicitado.")]
      end
      return [false, _INTL("Editor F7 no disponible.")]
    when "open_quick_saves"
      if defined?(SebiSaveManager)
        return [SebiSaveManager.open_quick_window, _INTL("Ventana de partidas solicitada.")]
      end
      return [false, _INTL("Gestor de partidas no disponible.")]
    when "open_hub_window"
      return [open_window, _INTL("Ventana F12 solicitada.")]
    when "open_sebilink_menu"
      return run_menu_action(_INTL("Menu SebiLink interno abierto.")) { SebiPokeLinkMenu.open_main_menu if defined?(SebiPokeLinkMenu) }
    when "open_multiplayer_menu"
      return run_menu_action(_INTL("Menu Multijugador abierto.")) { SebiVisualMultiplayer.open_main_menu if defined?(SebiVisualMultiplayer) }
    when "create_room"
      return run_menu_action(_INTL("Crear sala solicitado.")) { SebiVisualMultiplayer.create_room if defined?(SebiVisualMultiplayer) }
    when "create_room_direct"
      return run_menu_action(_INTL("Crear sala solicitado.")) do
        SebiVisualMultiplayer.create_room_direct(args["host"], args["port"], args["name"]) if defined?(SebiVisualMultiplayer)
      end
    when "join_room"
      return run_menu_action(_INTL("Unirse a sala solicitado.")) { SebiVisualMultiplayer.join_room if defined?(SebiVisualMultiplayer) }
    when "join_room_direct"
      return run_menu_action(_INTL("Unirse a sala solicitado.")) do
        SebiVisualMultiplayer.join_room_direct(args["host"], args["port"], args["name"]) if defined?(SebiVisualMultiplayer)
      end
    when "players_menu"
      return run_menu_action(_INTL("Jugadores conectados abierto.")) { SebiVisualMultiplayer.open_players_menu if defined?(SebiVisualMultiplayer) }
    when "teleport_to_player"
      SebiVisualMultiplayer.open_teleport_menu if defined?(SebiVisualMultiplayer)
      return [true, _INTL("TP a jugador solicitado.")]
    when "follow_player"
      return run_menu_action(_INTL("Seguir jugador solicitado.")) { SebiVisualMultiplayer.open_follow_menu if defined?(SebiVisualMultiplayer) }
    when "stop_following"
      SebiVisualMultiplayer.stop_following if defined?(SebiVisualMultiplayer)
      return [true, _INTL("Dejar de seguir solicitado.")]
    when "configure_pvp_battle"
      return run_menu_action(_INTL("Seleccion de combate PvP abierta.")) { SebiVisualMultiplayer.open_battle_menu if defined?(SebiVisualMultiplayer) }
    when "spectate_player"
      return run_menu_action(_INTL("Modo espectador solicitado.")) { SebiVisualMultiplayer.open_spectator_menu if defined?(SebiVisualMultiplayer) }
    when "stop_spectating"
      SebiBattleSpectator.stop_watching if defined?(SebiBattleSpectator)
      return [true, _INTL("Modo espectador detenido.")]
    when "map_markers"
      return run_menu_action(_INTL("Marcadores del mapa abiertos.")) { SebiVisualMultiplayer.open_marker_menu if defined?(SebiVisualMultiplayer) }
    when "clear_map_marker"
      SebiVisualMultiplayer.clear_shared_marker if defined?(SebiVisualMultiplayer)
      return [true, _INTL("Marcador compartido borrado.")]
    when "leave_room"
      return run_menu_action(_INTL("Abandonar/cerrar sala solicitado.")) { SebiVisualMultiplayer.leave_room if defined?(SebiVisualMultiplayer) }
    when "open_cheats_menu"
      return run_menu_action(_INTL("Menu Trucos abierto.")) { SebiCheats.open_menu if defined?(SebiCheats) }
    when "open_randomizer_menu"
      return run_menu_action(_INTL("Randomizador abierto.")) { SebiRandomizer.open_menu if defined?(SebiRandomizer) }
    when "check_sebilink_updates"
      return run_menu_action(_INTL("Busqueda de actualizaciones solicitada.")) { SebiLinkUpdater.check_now if defined?(SebiLinkUpdater) }
    when "wonder_trade_daily"
      return run_menu_action(_INTL("Intercambio prodigio solicitado.")) { SebiSpecialActions.wonder_trade_daily if defined?(SebiSpecialActions) }
    when "random_egg_trade_daily"
      return run_menu_action(_INTL("Intercambio huevo aleatorio solicitado.")) { SebiSpecialActions.random_egg_trade_daily if defined?(SebiSpecialActions) }
    when "training_battle"
      return run_menu_action(_INTL("Entrenamiento solicitado.")) { SebiSpecialActions.start_training_battle if defined?(SebiSpecialActions) }
    when "saved_teams_menu"
      return run_menu_action(_INTL("Equipos guardados abierto.")) { SebiSavedTeams.open_manager if defined?(SebiSavedTeams) }
    when "open_pokemon_center_menu"
      return run_menu_action(_INTL("Centro Pokemon abierto.")) { SebiPokemonCenter.open_menu if defined?(SebiPokemonCenter) }
    when "pokemon_center_heal"
      return run_menu_action(_INTL("Curacion Centro Pokemon solicitada.")) { SebiPokemonCenter.heal_party if defined?(SebiPokemonCenter) }
    when "pokemon_center_move_reminder"
      return run_menu_action(_INTL("Recordador de movimientos solicitado.")) { SebiPokemonCenter.open_move_reminder if defined?(SebiPokemonCenter) }
    when "pokemon_center_leader_levels"
      return run_menu_action(_INTL("Niveles de lideres solicitados.")) { SebiPokemonCenter.show_leader_levels if defined?(SebiPokemonCenter) }
    when "pokemon_center_open_pc"
      return run_menu_action(_INTL("PC Centro Pokemon solicitado.")) { SebiPokemonCenter.open_pc if defined?(SebiPokemonCenter) }
    when "pokemon_center_shops"
      return run_menu_action(_INTL("Menu de tiendas solicitado.")) { SebiPokemonCenter.open_shop_menu if defined?(SebiPokemonCenter) }
    when "pokemon_center_forms"
      return run_menu_action(_INTL("Cambiar formas solicitado.")) { SebiPokemonCenter.open_form_menu if defined?(SebiPokemonCenter) }
    when "pokemon_center_abilities"
      return run_menu_action(_INTL("Cambiar habilidades solicitado.")) { SebiPokemonCenter.open_ability_menu if defined?(SebiPokemonCenter) }
    when "pokemon_center_trades"
      return run_menu_action(_INTL("Intercambio Pokemon solicitado.")) { SebiPokemonCenter.open_trade_menu if defined?(SebiPokemonCenter) }
    when "change_shiny"
      return run_menu_action(_INTL("Shiny salvajes solicitado.")) { SebiCheats.change_wild_shiny_percent if defined?(SebiCheats) }
    when "set_wild_shiny_percent_value"
      return run_menu_action(_INTL("Shiny salvajes solicitado.")) do
        SebiCheats.set_wild_shiny_percent_value(args["percent"] || args["value"]) if defined?(SebiCheats)
      end
    when "transfer_shiny"
      return run_menu_action(_INTL("Mover shiny solicitado.")) { SebiCheats.transfer_shiny if defined?(SebiCheats) }
    when "change_level_cap"
      return run_menu_action(_INTL("Level cap solicitado.")) { SebiCheats.change_level_cap if defined?(SebiCheats) }
    when "set_level_cap_value"
      return run_menu_action(_INTL("Level cap solicitado.")) do
        SebiCheats.set_level_cap_value(args["level"] || args["value"]) if defined?(SebiCheats)
      end
    when "toggle_repel"
      return run_menu_action(_INTL("Repelente max alternado.")) { SebiCheats.toggle_max_repel if defined?(SebiCheats) }
    when "give_ashes"
      return run_menu_action(_INTL("Cenizas Sagradas solicitadas.")) { SebiCheats.give_sacred_ashes if defined?(SebiCheats) }
    when "give_ashes_quantity"
      return run_menu_action(_INTL("Cenizas Sagradas solicitadas.")) do
        SebiCheats.give_sacred_ashes_quantity(args["quantity"] || args["value"]) if defined?(SebiCheats)
      end
    when "toggle_collisions"
      return run_menu_action(_INTL("Colisiones alternadas.")) { SebiLinkOptions.toggle_remote_collisions if defined?(SebiLinkOptions) }
    when "open_backups_menu"
      return run_menu_action(_INTL("Guardados automaticos abierto.")) { SebiAutoBackups.open_menu if defined?(SebiAutoBackups) }
    when "create_backup"
      return run_menu_action(_INTL("Respaldo manual solicitado.")) do
        if defined?(SebiAutoBackups)
          ok, msg = SebiAutoBackups.create_backup("manual", true)
          Kernel.pbMessage(msg)
        end
      end
    when "load_backup"
      return [SebiSaveManager.open_window, _INTL("Ventana de partidas solicitada.")] if defined?(SebiSaveManager)
      return run_menu_action(_INTL("Cargar respaldo solicitado.")) { SebiAutoBackups.open_load_menu if defined?(SebiAutoBackups) }
    when "open_extra_controls"
      return run_menu_action(_INTL("Controles extra abierto.")) { SebiExtraControls.open_menu if defined?(SebiExtraControls) }
    else
      return [false, _INTL("Accion F12 desconocida: {1}", action.to_s)]
    end
  rescue Exception
    return [false, _INTL("Error ejecutando accion F12: {1}", $!.message.to_s)]
  end

  def self.process_commands
    return if @processing_command
    path = command_path
    return if !FileTest.exist?(path)
    text = ""
    File.open(path, "rb") { |file| text = file.read }
    return if !text || text == ""
    File.open(path, "wb") { |file| file.write("") }
    @processing_command = true
    text.each_line do |line|
      command = parse_command(line)
      next if !command || command["cmd"].to_s == ""
      ok, message = run_action(command["cmd"].to_s, command["args"] || {})
      write_result(command["seq"], ok, message)
    end
  rescue Exception
    write_result("error", false, _INTL("Error leyendo acciones F12: {1}", $!.message.to_s))
  ensure
    @processing_command = false
  end

  def self.update
    frame = Graphics.frame_count rescue 0
    return if @last_command_poll_frame && frame - @last_command_poll_frame < COMMAND_POLL_FRAMES
    @last_command_poll_frame = frame
    process_commands
  rescue Exception
  end

  def self.show_text(title, lines)
    Kernel.pbMessage(title.to_s + "\n" + lines.join("\n"))
  rescue Exception
  end

  def self.show_hotkeys
    show_text(_INTL("SebiLink - Teclas rapidas"), [
      _INTL("F12: abre esta guia general."),
      _INTL("F7: abre SebiHeX, el editor de partida."),
      _INTL("{1}: PokemonDB desde combate, equipo, resumen o recordador.", db_key_name),
      _INTL("{1}: muestra/oculta debilidades en combate.", weakness_key_name),
      _INTL("{1}: iguala niveles en Equipo o caja actual del PC.", level_key_name),
      _INTL("F1: controles originales del juego."),
      _INTL("F5: objeto registrado original."),
      _INTL("Ctrl+Z / Ctrl+Y: deshacer/rehacer dentro de SebiHeX.")
    ])
  end

  def self.show_battle_info
    show_text(_INTL("SebiLink - Combate y PokemonDB"), [
      _INTL("{1}: abre PokemonDB de los rivales visibles.", db_key_name),
      _INTL("{1}: en resumen, party, Pokedex o recordador abre el Pokemon actual.", db_key_name),
      _INTL("{1}: alterna el overlay de debilidades en combate.", weakness_key_name),
      _INTL("Los movimientos se colorean por efectividad cuando hay objetivo."),
      _INTL("En cambios de entrenador, PokemonDB puede abrir el proximo rival."),
      _INTL("En combates SebiLink no se permite usar la mochila.")
    ])
  end

  def self.show_editor_info
    show_text(_INTL("SebiLink - Editor F7"), [
      _INTL("F7 abre SebiHeX con Equipo, PC, editor Pokemon y SAV."),
      _INTL("SAV incluye Datos, Cajas, Entrenador, Pokedex, Objetos, Logros y Switches."),
      _INTL("Los cambios quedan pendientes hasta Archivo > Guardar partida."),
      _INTL("Archivo > Actualizar recarga el snapshot y descarta cambios no guardados."),
      _INTL("Edicion > Historial de acciones permite volver a estados locales.")
    ])
  end

  def self.show_multiplayer_info
    show_text(_INTL("SebiLink - Multijugador"), [
      _INTL("SebiLink > Multijugador > Crear sala inicia servidor local."),
      _INTL("Los invitados usan Unirse a sala con la IP Tailscale del anfitrion."),
      _INTL("Jugadores conectados permite elegir jugador remoto."),
      _INTL("Mirar a un jugador remoto y pulsar accion abre su menu."),
      _INTL("Tambien puedes hacer click en un jugador remoto para seguirlo o hacer TP."),
      _INTL("Opciones remotas: TP, seguir, espectar, intercambio y combates."),
      _INTL("Combatir abre la configuracion y envia la solicitud con esas reglas."),
      _INTL("En el mapa regional normal, el boton X comparte un marcador durante 1 minuto."),
      _INTL("Mientras sigues a alguien, el boton B pregunta si quieres dejar de seguir."),
      _INTL("Abandonar/cerrar sala corta la sesion actual.")
    ])
  end

  def self.show_cheats_info
    show_text(_INTL("SebiLink - Trucos y equipo"), [
      _INTL("Shiny salvajes ajusta el porcentaje de shiny."),
      _INTL("Mover shiny cambia el shiny entre Pokemon del equipo y del PC."),
      _INTL("Level cap permite fijar limite temporal."),
      _INTL("Repelente max desactiva encuentros salvajes aleatorios."),
      _INTL("Igualar niveles del equipo sube al mas alto permitido."),
      _INTL("{1}: iguala equipo o caja actual del PC segun pantalla.", level_key_name),
      _INTL("Dar Cenizas Sagradas entrega la cantidad elegida.")
    ])
  end

  def self.show_system_info
    show_text(_INTL("SebiLink - Sistema"), [
      _INTL("Colisiones jugadores activa o desactiva choque con remotos."),
      _INTL("Guardados automaticos crea respaldos cada 5 minutos."),
      _INTL("Desde Guardados automaticos puedes crear o cargar respaldos."),
      _INTL("Controles extra permite cambiar {1}, {2} y {3}.", db_key_name, weakness_key_name, level_key_name),
      _INTL("Este hub F12 debe actualizarse cada vez que se anada una funcion SebiLink.")
    ])
  end

  def self.open_editor
    if defined?(SebiSaveEditor)
      SebiSaveEditor.open_editor
    else
      Kernel.pbMessage(_INTL("El editor F7 no esta disponible."))
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir el editor F7."))
  end

  def self.open_menu
    open_window
  end
end

module SebiPokemonCenter
  POKEVIAL_CURRENT_VAR = 238
  POKEVIAL_MAX_VAR = 239
  ABILITY_COST_ITEM = :TINYMUSHROOM

  @catalog_scanned = false
  @shops = []
  @trades = []

  def self.open_menu
    loop do
      commands = [
        _INTL("Curar equipo"),
        _INTL("Recordar movs"),
        _INTL("Niveles lideres"),
        _INTL("Abrir PC"),
        _INTL("Menu de tiendas"),
        _INTL("Cambiar formas"),
        _INTL("Cambiar habilidades"),
        _INTL("Intercambio Pokemon"),
        _INTL("Salir")
      ]
      cmd = Kernel.pbMessage(_INTL("Centro Pokemon"), commands, commands.length)
      case cmd
      when 0
        heal_party
      when 1
        open_move_reminder
      when 2
        show_leader_levels
      when 3
        open_pc
      when 4
        open_shop_menu
      when 5
        open_form_menu
      when 6
        open_ability_menu
      when 7
        open_trade_menu
      else
        break
      end
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir Centro Pokemon: {1}", $!.message.to_s))
  end

  def self.heal_party
    if defined?(pbHealAll)
      pbHealAll
    elsif $Trainer && $Trainer.party
      for pokemon in $Trainer.party
        pokemon.heal if pokemon
      end
    end
    if $game_variables && $game_variables[POKEVIAL_MAX_VAR].to_i > 0
      $game_variables[POKEVIAL_CURRENT_VAR] = $game_variables[POKEVIAL_MAX_VAR].to_i
    end
    $game_map.need_refresh = true if $game_map
    Kernel.pbMessage(_INTL("Tu equipo ha sido curado y los Pokeviales se han restablecido."))
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo curar el equipo: {1}", $!.message.to_s))
  end

  def self.open_move_reminder
    if !$Trainer || !$Trainer.party || $Trainer.party.length == 0
      Kernel.pbMessage(_INTL("No tienes Pokemon en el equipo."))
      return
    end
    if defined?(pbChoosePokemon) && defined?(pbGetPokemon)
      Kernel.pbMessage(_INTL("Que Pokemon deberia recordar un movimiento?"))
      pbChoosePokemon(1, 3, proc { |p|
        ok = p ? true : false
        ok = false if ok && p.respond_to?(:egg?) && p.egg?
        ok = false if ok && (p.isShadow? rescue false)
        ok = false if ok && defined?(pbHasRelearnableMove?) && !pbHasRelearnableMove?(p)
        ok
      }, true)
      return if !$game_variables || $game_variables[1].to_i < 0
      pokemon = pbGetPokemon(1)
    else
      choices = []
      for pokemon in $Trainer.party
        choices.push(pokemon ? pokemon.name : _INTL("Vacio"))
      end
      choices.push(_INTL("Cancelar"))
      index = Kernel.pbMessage(_INTL("Elige Pokemon."), choices, choices.length)
      return if index < 0 || index >= $Trainer.party.length
      pokemon = $Trainer.party[index]
    end
    if !pokemon
      Kernel.pbMessage(_INTL("No se eligio ningun Pokemon."))
      return
    end
    if defined?(pbHasRelearnableMove?) && !pbHasRelearnableMove?(pokemon)
      Kernel.pbMessage(_INTL("Parece que {1} no puede recordar ningun movimiento.", pokemon.name))
      return
    end
    if defined?(pbRelearnMoveScreen)
      pbRelearnMoveScreen(pokemon)
    else
      Kernel.pbMessage(_INTL("El recordador de movimientos no esta disponible."))
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir el recordador: {1}", $!.message.to_s))
  end

  def self.open_ability_menu
    if !$PokemonBag || !$PokemonBag.pbHasItem?(ABILITY_COST_ITEM)
      Kernel.pbMessage(_INTL("Necesitas una Mini Seta para cambiar la habilidad de un Pokemon."))
      return
    end
    return if !Kernel.pbConfirmMessage(_INTL("Cambiar una habilidad cuesta 1 Mini Seta. Continuar?"))
    changed = false
    if defined?(pbChangeAbility)
      changed = pbChangeAbility ? true : false
    else
      changed = change_ability_fallback
    end
    return if !changed
    if $PokemonBag.pbDeleteItem(ABILITY_COST_ITEM, 1)
      $game_map.need_refresh = true if $game_map
      Kernel.pbMessage(_INTL("La habilidad ha cambiado. Se ha gastado 1 Mini Seta."))
    else
      Kernel.pbMessage(_INTL("La habilidad ha cambiado, pero no se pudo descontar la Mini Seta."))
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo cambiar la habilidad: {1}", $!.message.to_s))
  end

  def self.change_ability_fallback
    if !$Trainer || !$Trainer.party || $Trainer.party.length == 0
      Kernel.pbMessage(_INTL("No tienes Pokemon en el equipo."))
      return false
    end
    if defined?(pbChoosePokemon) && defined?(pbGetPokemon)
      pbChoosePokemon(1, 2, proc { |poke|
        poke && !poke.isEgg? && !(poke.isShadow? rescue false) && poke.getAbilityList.length > 1
      })
      return false if !$game_variables || $game_variables[1].to_i < 0
      pokemon = pbGetPokemon(1)
    else
      eligible = []
      for i in 0...$Trainer.party.length
        poke = $Trainer.party[i]
        next if !poke || poke.isEgg? || (poke.isShadow? rescue false) || poke.getAbilityList.length <= 1
        eligible.push([i, poke])
      end
      if eligible.length == 0
        Kernel.pbMessage(_INTL("No tienes Pokemon validos con mas de una habilidad."))
        return false
      end
      commands = eligible.collect { |entry| entry[1].name }
      commands.push(_INTL("Cancelar"))
      cmd = Kernel.pbMessage(_INTL("Elige Pokemon."), commands, commands.length)
      return false if cmd < 0 || cmd >= eligible.length
      pokemon = eligible[cmd][1]
    end
    return false if !pokemon
    abilities = pokemon.getAbilityList
    if !abilities || abilities.length <= 1
      Kernel.pbMessage(_INTL("Ese Pokemon no tiene otra habilidad disponible."))
      return false
    end
    current_ability = pokemon.abilityIndex
    ability_options = []
    ability_descs = []
    for ability in abilities
      name = PBAbilities.getName(ability[0]) rescue ability[0].to_s
      name += _INTL(" (H)") if ability[1].to_i >= 2
      desc = pbGetMessage(MessageTypes::AbilityDescs, ability[0]) rescue ""
      ability_options.push(name)
      ability_descs.push(desc)
    end
    if Kernel.respond_to?(:pbMessageWithHelp)
      chosen = Kernel.pbMessageWithHelp(_INTL("Que habilidad quieres para {1}?", pokemon.name), ability_options, ability_descs, -1)
    else
      ability_options.push(_INTL("Cancelar"))
      chosen = Kernel.pbMessage(_INTL("Que habilidad quieres para {1}?", pokemon.name), ability_options, ability_options.length)
    end
    return false if chosen < 0 || chosen >= abilities.length
    if current_ability == abilities[chosen][1]
      Kernel.pbMessage(_INTL("Tu Pokemon ya posee esa habilidad."))
      return false
    end
    pokemon.setAbility(abilities[chosen][1])
    pokemon.calcStats if pokemon.respond_to?(:calcStats)
    return true
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo cambiar la habilidad: {1}", $!.message.to_s))
    return false
  end

  def self.show_leader_levels
    return run_common_event_by_name("Niveles de lideres", _INTL("No se encontro el evento de niveles de lideres."))
  end

  def self.open_pc
    if defined?(pbPokeCenterPC)
      pbPokeCenterPC
    elsif defined?(pbTrainerPC)
      pbTrainerPC
    else
      Kernel.pbMessage(_INTL("El PC no esta disponible ahora."))
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir el PC: {1}", $!.message.to_s))
  end

  def self.open_form_menu
    commands = [
      _INTL("Forma exotica"),
      _INTL("Forma comun"),
      _INTL("Cancelar")
    ]
    cmd = Kernel.pbMessage(_INTL("Cambiar formas"), commands, commands.length)
    case cmd
    when 0
      run_common_event_by_name("Transformador Exotico", _INTL("No se encontro el Transformador Exotico."))
    when 1
      run_common_event_by_name("Transformador Comun", _INTL("No se encontro el Transformador Comun."))
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir cambiar formas: {1}", $!.message.to_s))
  end

  def self.open_shop_menu
    shops = shop_catalog
    if shops.length == 0
      Kernel.pbMessage(_INTL("No se encontraron tiendas indexables."))
      return
    end
    loop do
      commands = shops.collect { |shop| shop["label"] }
      commands.push(_INTL("Cancelar"))
      cmd = Kernel.pbMessage(_INTL("Menu de tiendas"), commands, commands.length)
      break if cmd < 0 || cmd >= shops.length
      execute_shop(shops[cmd])
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir tiendas: {1}", $!.message.to_s))
  end

  def self.open_trade_menu
    trades = trade_catalog
    if trades.length == 0
      Kernel.pbMessage(_INTL("No se encontraron intercambios Pokemon fijos."))
      return
    end
    loop do
      commands = trades.collect { |trade| trade["label"] }
      commands.push(_INTL("Cancelar"))
      cmd = Kernel.pbMessage(_INTL("Intercambio Pokemon"), commands, commands.length)
      break if cmd < 0 || cmd >= trades.length
      execute_trade(trades[cmd])
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir intercambios: {1}", $!.message.to_s))
  end

  def self.run_common_event_by_name(name, missing_message)
    id = common_event_id(name)
    if !id
      Kernel.pbMessage(missing_message)
      return false
    end
    pbCommonEvent(id)
    return true
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo ejecutar el evento: {1}", $!.message.to_s))
    return false
  end

  def self.common_event_id(name)
    return nil if !$data_common_events
    target = normalize_name(name)
    for i in 0...$data_common_events.length
      event = $data_common_events[i]
      next if !event || !event.respond_to?(:name)
      return i if normalize_name(event.name) == target
    end
    return nil
  rescue Exception
    return nil
  end

  def self.shop_catalog
    ensure_catalog
    return @shops || []
  end

  def self.trade_catalog
    ensure_catalog
    return @trades || []
  end

  def self.ensure_catalog
    return if @catalog_scanned
    @shops = []
    @trades = []
    shop_seen = {}
    trade_seen = {}
    paths = Dir.glob("Data/Map*.rxdata") rescue []
    paths.sort.each_with_index do |path, index|
      map_id = path.to_s[/Map(\d+)\.rxdata/i, 1].to_i rescue 0
      next if map_id <= 0
      text = ""
      File.open(path, "rb") { |file| text = file.read.to_s } rescue text = ""
      next if text == ""
      scan_shop_raw_text(text, map_id, shop_seen)
      scan_trade_raw_text(text, map_id, trade_seen)
      if index % 60 == 0
        Graphics.update rescue nil
        Input.update rescue nil
      end
    end
    finalize_catalog_labels
    @catalog_scanned = true
  rescue Exception
    @catalog_scanned = true
    Kernel.pbMessage(_INTL("No se pudo indexar el mundo: {1}", $!.message.to_s))
  end

  def self.finalize_catalog_labels
    @shops.sort! { |a, b| a["fullLabel"].to_s <=> b["fullLabel"].to_s }
    @trades.sort! { |a, b| a["fullLabel"].to_s <=> b["fullLabel"].to_s }
    for i in 0...@shops.length
      @shops[i]["label"] = sprintf("%02d: %s", i + 1, @shops[i]["label"].to_s)
    end
    for i in 0...@trades.length
      @trades[i]["label"] = sprintf("%02d: %s", i + 1, @trades[i]["label"].to_s)
    end
  rescue Exception
  end

  def self.scan_shop_raw_text(text, map_id, seen)
    offset = 0
    loop do
      start = text.index("pbPokemonMart", offset) rescue nil
      break if !start
      close = text.index("]);", start) rescue nil
      close = start + 1800 if !close || close > start + 1800
      segment = text[start, close - start + 3].to_s
      stock = parse_shop_stock(segment)
      if stock.length > 0
        key = map_id.to_s + "|" + stock.join(",")
        if !seen[key]
          seen[key] = true
          full_label = sprintf("Mapa %03d: %s", map_id.to_i, stock.join(","))
          @shops.push({
            "label" => shop_menu_label(stock),
            "fullLabel" => full_label,
            "stock" => stock,
            "mapId" => map_id,
            "eventId" => 0
          })
        end
      end
      offset = start + 12
    end
  rescue Exception
  end

  def self.scan_trade_raw_text(text, map_id, seen)
    return if text.to_s !~ /pbRemovePokemonAt\s*\(\s*0\s*\)/
    offset = 0
    pattern = /\$Trainer\.pokemonParty\[0\]\.species\s*==\s*PBSpecies::([A-Za-z0-9_]+)/
    loop do
      remaining = text[offset..-1]
      break if !remaining
      match = remaining.match(pattern)
      break if !match
      base = offset + match.begin(0)
      give = match[1].to_s
      segment = text[base, 1600].to_s
      if segment =~ /pbRemovePokemonAt\s*\(\s*0\s*\).*?pbAddPokemon\s*\(\s*(?::|PBSpecies::)?([A-Za-z0-9_]+)\s*,\s*(\d+)/m
        receive = $1.to_s
        level = $2.to_i
        key = map_id.to_s + "|" + give + "|" + receive + "|" + level.to_s
        if !seen[key]
          seen[key] = true
          full_label = trade_label(sprintf("Mapa %03d", map_id.to_i), give, receive, level)
          @trades.push({
            "label" => trade_menu_label(give, receive),
            "fullLabel" => full_label,
            "give" => give,
            "receive" => receive,
            "level" => level,
            "mapId" => map_id,
            "eventId" => 0
          })
        end
      end
      offset = base + match.end(0)
    end
  rescue Exception
  end

  def self.collect_script_blocks(list)
    blocks = []
    current = nil
    for command in list
      code = command.code rescue 0
      text = command.parameters[0].to_s rescue ""
      if code == 355
        blocks.push(current) if current && current != ""
        current = text
      elsif code == 655
        current = "" if !current
        current += "\n" + text
      elsif code == 111
        params = command.parameters rescue []
        if params && params[0] && params[0].to_i == 12 && params[1].to_s != ""
          blocks.push(current) if current && current != ""
          current = nil
          blocks.push(params[1].to_s)
        end
      else
        blocks.push(current) if current && current != ""
        current = nil
      end
    end
    blocks.push(current) if current && current != ""
    return blocks
  rescue Exception
    return []
  end

  def self.scan_shop_scripts(scripts, map_id, map_name, event, seen)
    for script in scripts
      next if script !~ /pbPokemonMart\s*\(/
      stock = parse_shop_stock(script)
      next if stock.length == 0
      key = map_id.to_s + "|" + event.id.to_s + "|" + stock.join(",")
      next if seen[key]
      seen[key] = true
      full_label = shop_label(map_name, event.name, stock)
      @shops.push({
        "label" => shop_menu_label(stock),
        "fullLabel" => full_label,
        "stock" => stock,
        "mapId" => map_id,
        "eventId" => event.id
      })
    end
  rescue Exception
  end

  def self.scan_trade_scripts(scripts, map_id, map_name, event, seen)
    script_text = scripts.join("\n")
    return if script_text !~ /pbRemovePokemonAt\s*\(\s*0\s*\)/
    offset = 0
    pattern = /\$Trainer\.pokemonParty\[0\]\.species\s*==\s*PBSpecies::([A-Za-z0-9_]+)/
    loop do
      remaining = script_text[offset..-1]
      break if !remaining
      match = remaining.match(pattern)
      break if !match
      base = offset + match.begin(0)
      give = match[1].to_s
      segment = script_text[base, 1200]
      if segment && segment =~ /pbRemovePokemonAt\s*\(\s*0\s*\).*?pbAddPokemon\s*\(\s*(?::|PBSpecies::)?([A-Za-z0-9_]+)\s*,\s*(\d+)/m
        receive = $1.to_s
        level = $2.to_i
        key = map_id.to_s + "|" + event.id.to_s + "|" + give + "|" + receive + "|" + level.to_s
        if !seen[key]
          seen[key] = true
          full_label = trade_label(map_name, give, receive, level)
          @trades.push({
            "label" => trade_menu_label(give, receive),
            "fullLabel" => full_label,
            "give" => give,
            "receive" => receive,
            "level" => level,
            "mapId" => map_id,
            "eventId" => event.id
          })
        end
      end
      offset = base + match.end(0)
    end
  rescue Exception
  end

  def self.parse_shop_stock(script)
    stock = []
    source = script.to_s
    source = $1.to_s if source =~ /pbPokemonMart\s*\(\s*\[([^\]]*)\]/m
    source.scan(/:([A-Za-z0-9_]+)/) do |match|
      name = match[0].to_s
      item = name.to_sym
      stock.push(item) if name != "" && !stock.include?(item)
    end
    return stock
  rescue Exception
    return []
  end

  def self.execute_shop(shop)
    if !shop || !shop["stock"] || shop["stock"].length == 0
      Kernel.pbMessage(_INTL("Esta tienda no tiene stock valido."))
      return
    end
    pbPokemonMart(shop["stock"])
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir la tienda: {1}", $!.message.to_s))
  end

  def self.execute_trade(trade)
    if !$Trainer || !$Trainer.party || !$Trainer.party[0]
      Kernel.pbMessage(_INTL("Necesitas un Pokemon en el primer puesto del equipo."))
      return
    end
    give_id = species_id(trade["give"])
    receive_sym = trade["receive"].to_s.to_sym
    level = trade["level"].to_i
    give_name = species_name(trade["give"])
    receive_name = species_name(trade["receive"])
    if !give_id || $Trainer.party[0].species != give_id
      Kernel.pbMessage(_INTL("Pon a {1} en el primer puesto del equipo para hacer este intercambio.", give_name))
      return
    end
    random_received = nil
    if defined?(SebiRandomizer) && SebiRandomizer.active?("npc_trade")
      row = SebiRandomizer.choose("npc_trade")
      random_received = SebiRandomizer.context(nil) { PokeBattle_Pokemon.new(row[0], level, $Trainer) }
      random_received.form = SebiRandomizer.form_for(row)
      SebiRandomizer.prepare_pokemon(random_received)
      random_received.resetMoves
      SebiRandomizer.ensure_attack(random_received)
      receive_name = PBSpecies.getName(random_received.species)
    end
    return if !Kernel.pbConfirmMessage(_INTL("Intercambiar {1} por {2} Nv. {3}?", give_name, receive_name, level))
    if !pbRemovePokemonAt(0)
      Kernel.pbMessage(_INTL("No se pudo retirar a {1}. Necesitas conservar al menos otro Pokemon util.", give_name))
      return
    end
    if defined?(SebiRandomizer)
      # Preserve independence from Pokemon gifts, including when NPC swaps are OFF.
      SebiRandomizer.context("npc_trade") { pbAddPokemon(random_received || receive_sym, level) }
    else
      pbAddPokemon(receive_sym, level)
    end
    Kernel.pbMessage(_INTL("Intercambio completado: recibiste a {1}.", receive_name))
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo completar el intercambio: {1}", $!.message.to_s))
  end

  def self.shop_label(map_name, event_name, stock)
    names = stock[0, 3].collect { |item| item_name(item) }
    suffix = stock.length > 3 ? _INTL(" y {1} mas", stock.length - 3) : ""
    event_text = event_name && event_name.to_s != "" ? " - " + event_name.to_s : ""
    return map_name.to_s + event_text + ": " + names.join(", ") + suffix
  rescue Exception
    return map_name.to_s
  end

  def self.shop_menu_label(stock)
    first = stock && stock.length > 0 ? item_name(stock[0]) : _INTL("Tienda")
    label = shorten_menu_text(first, 20)
    label += _INTL(" +{1}", stock.length - 1) if stock && stock.length > 1
    return label
  rescue Exception
    return _INTL("Tienda")
  end

  def self.shorten_menu_text(text, max_length)
    value = text.to_s
    return value if value.length <= max_length
    limit = max_length - 3
    result = ""
    parts = value.split(/\s+/)
    for part in parts
      candidate = result == "" ? part : result + " " + part
      break if candidate.length > limit
      result = candidate
    end
    result = value[0, limit].to_s if result == ""
    return result + "..."
  end

  def self.trade_label(map_name, give, receive, level)
    return _INTL("{1} -> {2} Nv. {3} - {4}", species_name(give), species_name(receive), level, map_name)
  end

  def self.trade_menu_label(give, receive)
    return _INTL("{1} -> {2}", shorten_menu_text(species_name(give), 10), shorten_menu_text(species_name(receive), 10))
  rescue Exception
    return _INTL("Intercambio")
  end

  def self.map_label(map_infos, map_id)
    info = map_infos[map_id] rescue nil
    name = info && info.respond_to?(:name) ? info.name.to_s : ""
    name = sprintf("Mapa %03d", map_id.to_i) if name == ""
    return name
  rescue Exception
    return sprintf("Mapa %03d", map_id.to_i)
  end

  def self.item_name(item)
    id = getID(PBItems, item) rescue nil
    return PBItems.getName(id) if id && id.to_i > 0 && defined?(PBItems)
    return item.to_s
  rescue Exception
    return item.to_s
  end

  def self.species_id(species)
    begin
      return getID(PBSpecies, species.to_s.to_sym)
    rescue Exception
      return nil
    end
  end

  def self.species_name(species)
    id = species_id(species)
    return PBSpecies.getName(id) if id && id.to_i > 0 && defined?(PBSpecies)
    return species.to_s
  rescue Exception
    return species.to_s
  end

  def self.normalize_name(value)
    return value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
  end
end

module SebiSpecialActions
  DATA_IVAR = :@sebi_pokelink_special_actions
  TRAINING_OPTIONS = [
    [:WOBBUFFET, "Wobbuffet", 58],
    [:CELEBI, "Celebi", 100],
    [:ARCEUS, "Arceus", 120]
  ]
  QUALITY_TIERS = [
    [0, 249, "bastante malo"],
    [250, 349, "malo"],
    [350, 449, "normal"],
    [450, 534, "bueno"],
    [535, 999, "increible"]
  ]

  @species_cache = nil

  def self.data
    if !$PokemonGlobal
      @fallback_data = {} if !@fallback_data.is_a?(Hash)
      return @fallback_data
    end
    value = $PokemonGlobal.instance_variable_get(DATA_IVAR)
    value = {} if !value.is_a?(Hash)
    $PokemonGlobal.instance_variable_set(DATA_IVAR, value)
    return value
  rescue Exception
    @fallback_data = {} if !@fallback_data.is_a?(Hash)
    return @fallback_data
  end

  def self.today_key
    return Time.now.strftime("%Y-%m-%d")
  rescue Exception
    return "dia-" + ((Graphics.frame_count rescue 0) / 86400).to_s
  end

  def self.choose_party_index(message)
    return -1 if !$Trainer || !$Trainer.party || $Trainer.party.length == 0
    scene = PokemonScreen_Scene.new
    screen = PokemonScreen.new(scene, $Trainer.party)
    index = -1
    begin
      screen.pbStartScene(message, false)
      index = screen.pbChoosePokemon(message)
      screen.pbEndScene
    rescue Exception
      begin
        screen.pbEndScene
      rescue Exception
      end
      raise
    end
    return index
  end

  def self.species_id(symbol)
    return getID(PBSpecies, symbol) if defined?(PBSpecies)
    return nil
  rescue Exception
    return nil
  end

  def self.move_id(symbol)
    return getID(PBMoves, symbol) if defined?(PBMoves)
    return nil
  rescue Exception
    return nil
  end

  def self.base_total_for_species(id)
    pokemon = PokeBattle_Pokemon.new(id.to_i, 50)
    stats = pokemon.baseStats rescue nil
    return 0 if !stats || stats.length < 6
    total = 0
    for value in stats
      total += value.to_i
    end
    return total
  rescue Exception
    return 0
  end

  def self.species_entries
    return @species_cache if @species_cache
    entries = []
    if defined?(PBSpecies)
      for const_name in PBSpecies.constants
        id = nil
        begin
          id = PBSpecies.const_get(const_name)
        rescue Exception
          id = nil
        end
        next if !id || id.to_i <= 0
        name = PBSpecies.getName(id.to_i).to_s rescue ""
        next if name == "" || name == "?????"
        total = base_total_for_species(id.to_i)
        next if total <= 0
        entries.push([id.to_i, total])
      end
    end
    seen = {}
    clean = []
    for entry in entries
      next if seen[entry[0]]
      seen[entry[0]] = true
      clean.push(entry)
    end
    @species_cache = clean
    return @species_cache
  rescue Exception
    @species_cache = []
    return @species_cache
  end

  def self.trade_blocklist_path
    return File.expand_path("multiplayer/special-trades/blocked_species.txt")
  rescue Exception
    return "multiplayer/special-trades/blocked_species.txt"
  end

  def self.species_id_from_value(value)
    return value.to_i if value.is_a?(Numeric)
    text = value.to_s.strip
    return text.to_i if text =~ /\A\d+\z/
    return 0 if text == ""
    text = text.upcase.gsub(/[^A-Z0-9_]/, "")
    id = getID(PBSpecies, text.to_sym) rescue nil
    return id.to_i if id && id.to_i > 0
    id = PBSpecies.const_get(text) rescue nil
    return id.to_i if id && id.to_i > 0
    return 0
  rescue Exception
    return 0
  end

  def self.trade_blocked_species_ids
    path = trade_blocklist_path
    mtime = File.mtime(path).to_i rescue -1
    return @trade_blocked_species_ids if @trade_blocked_species_ids && @trade_blocklist_mtime == mtime
    blocked = {}
    if FileTest.exist?(path)
      File.open(path, "rb") do |file|
        file.each_line do |line|
          line = line.gsub(/\r|\n/, "")
          line = line.split("#")[0].to_s
          line.split(/[\s,;]+/).each do |token|
            id = species_id_from_value(token)
            blocked[id] = true if id > 0
          end
        end
      end
    end
    @trade_blocklist_mtime = mtime
    @trade_blocked_species_ids = blocked
    return @trade_blocked_species_ids
  rescue Exception
    @trade_blocked_species_ids = {}
    return @trade_blocked_species_ids
  end

  def self.max_species_id
    return PBSpecies.maxValue if defined?(PBSpecies) && PBSpecies.respond_to?(:maxValue)
    max = 0
    if defined?(PBSpecies)
      for const_name in PBSpecies.constants
        value = PBSpecies.const_get(const_name) rescue 0
        max = value.to_i if value.to_i > max
      end
    end
    return max
  rescue Exception
    return 0
  end

  def self.species_internal_name(species)
    @species_internal_names = nil if !@species_internal_names.is_a?(Hash)
    @species_internal_names = {} if !@species_internal_names
    if @species_internal_names.length == 0 && defined?(PBSpecies)
      for const_name in PBSpecies.constants
        id = PBSpecies.const_get(const_name) rescue nil
        next if !id || id.to_i <= 0
        @species_internal_names[id.to_i] = const_name.to_s.upcase
      end
    end
    return @species_internal_names[species.to_i].to_s
  rescue Exception
    return ""
  end

  def self.normalized_form_key(species)
    key = species_internal_name(species)
    return "" if key == ""
    key = key.upcase.gsub(/[^A-Z0-9]/, "")
    ["ALOLAN", "ALOLA", "GALARIAN", "GALAR", "HISUIAN", "HISUI", "PALDEAN", "PALDEA"].each do |token|
      key = key.gsub(token, "")
    end
    return key
  rescue Exception
    return ""
  end

  def self.form_variant_groups
    return @trade_form_variant_groups if @trade_form_variant_groups
    groups = {}
    max = max_species_id
    for id in 1..max
      key = normalized_form_key(id)
      next if key == ""
      groups[key] = [] if !groups[key]
      groups[key].push(id)
    end
    @trade_form_variant_groups = groups
    return @trade_form_variant_groups
  rescue Exception
    @trade_form_variant_groups = {}
    return @trade_form_variant_groups
  end

  def self.form_variant_ids(species)
    key = normalized_form_key(species)
    return [species.to_i] if key == ""
    ret = form_variant_groups[key] || []
    ret.push(species.to_i) if ret.length == 0
    return ret
  rescue Exception
    return [species.to_i]
  end

  def self.evolution_target_ids(species)
    ret = []
    data = pbGetEvolvedFormData(species.to_i) rescue []
    return ret if !data || data.length == 0
    if data[0].is_a?(Array)
      for evo in data
        target = 0
        begin
          target = evo[0]
        rescue Exception
          target = 0
        end
        id = species_id_from_value(target)
        ret.push(id) if id > 0
      end
    else
      i = 0
      while i < data.length
        id = species_id_from_value(data[i])
        ret.push(id) if id > 0
        i += 3
      end
    end
    return ret
  rescue Exception
    return []
  end

  def self.evolution_maps
    return [@trade_evo_children, @trade_evo_parents] if @trade_evo_children && @trade_evo_parents
    children = {}
    parents = {}
    max = max_species_id
    for species in 1..max
      targets = evolution_target_ids(species)
      children[species] = targets
      for target in targets
        parents[target] = [] if !parents[target]
        parents[target].push(species)
      end
    end
    @trade_evo_children = children
    @trade_evo_parents = parents
    return [@trade_evo_children, @trade_evo_parents]
  rescue Exception
    return [{}, {}]
  end

  def self.species_family(species)
    @trade_family_cache = {} if !@trade_family_cache
    species = species.to_i
    return @trade_family_cache[species] if @trade_family_cache[species]
    children, parents = evolution_maps
    seen = {}
    queue = [species]
    until queue.empty?
      current = queue.shift.to_i
      next if current <= 0 || seen[current]
      seen[current] = true
      for id in (children[current] || [])
        queue.push(id) if id.to_i > 0 && !seen[id.to_i]
      end
      for id in (parents[current] || [])
        queue.push(id) if id.to_i > 0 && !seen[id.to_i]
      end
      for id in form_variant_ids(current)
        queue.push(id) if id.to_i > 0 && !seen[id.to_i]
      end
    end
    @trade_family_cache[species] = seen.keys
    return @trade_family_cache[species]
  rescue Exception
    return [species.to_i]
  end

  def self.trainer_caught_species?(species)
    return false if !$Trainer
    species = species.to_i
    [:owned?, :isOwned?, :hasOwned?].each do |method_name|
      begin
        return true if $Trainer.respond_to?(method_name) && $Trainer.send(method_name, species)
      rescue Exception
      end
    end
    begin
      owned = $Trainer.owned if $Trainer.respond_to?(:owned)
      return true if owned && owned[species]
    rescue Exception
    end
    [:@owned, :@pokedexOwned, :@pokedex_owned].each do |ivar|
      begin
        value = $Trainer.instance_variable_get(ivar)
        return true if value.is_a?(Array) && value[species]
        return true if value.is_a?(Hash) && value[species]
      rescue Exception
      end
    end
    return false
  rescue Exception
    return false
  end

  def self.captured_family_species_ids
    blocked = {}
    max = max_species_id
    for species in 1..max
      next if !trainer_caught_species?(species)
      for family_id in species_family(species)
        blocked[family_id.to_i] = true
      end
    end
    if defined?(SebiBattleAdvisor)
      for ref in (SebiBattleAdvisor.owned_pokemon_refs rescue [])
        pokemon = ref["pokemon"] rescue nil
        next if !pokemon
        for family_id in species_family(pokemon.species.to_i)
          blocked[family_id.to_i] = true
        end
      end
    end
    return blocked
  rescue Exception
    return {}
  end

  def self.trade_unavailable_species_ids
    blocked = {}
    for key in trade_blocked_species_ids.keys
      blocked[key.to_i] = true
    end
    captured = captured_family_species_ids
    for key in captured.keys
      blocked[key.to_i] = true
    end
    return blocked
  rescue Exception
    return {}
  end

  def self.trade_species_allowed?(species, unavailable = nil)
    species = species.to_i
    return false if species <= 0
    unavailable = trade_unavailable_species_ids if !unavailable
    return false if unavailable[species]
    return true
  rescue Exception
    return false
  end

  def self.tier_for_total(total)
    total = total.to_i
    for tier in QUALITY_TIERS
      return tier if total >= tier[0] && total <= tier[1]
    end
    return QUALITY_TIERS[QUALITY_TIERS.length - 1]
  end

  def self.quality_label_for_total(total)
    tier = tier_for_total(total)
    return tier[2].to_s
  rescue Exception
    return "desconocido"
  end

  def self.random_species_for_total(total, original_species)
    tier = tier_for_total(total)
    candidates = []
    unavailable = trade_unavailable_species_ids
    for entry in species_entries
      next if entry[0].to_i == original_species.to_i
      next if !trade_species_allowed?(entry[0], unavailable)
      candidates.push(entry[0]) if entry[1].to_i >= tier[0] && entry[1].to_i <= tier[1]
    end
    if candidates.length == 0
      for entry in species_entries
        next if entry[0].to_i == original_species.to_i
        next if !trade_species_allowed?(entry[0], unavailable)
        candidates.push(entry[0]) if (entry[1].to_i - total.to_i).abs <= 80
      end
    end
    if candidates.length == 0
      for entry in species_entries
        next if !trade_species_allowed?(entry[0], unavailable)
        candidates.push(entry[0]) if entry[0].to_i != original_species.to_i
      end
    end
    return nil if candidates.length == 0
    return candidates[rand(candidates.length)]
  rescue Exception
    return nil
  end

  def self.random_any_species
    candidates = []
    unavailable = trade_unavailable_species_ids
    for entry in species_entries
      candidates.push(entry[0]) if trade_species_allowed?(entry[0], unavailable)
    end
    return nil if candidates.length == 0
    return candidates[rand(candidates.length)]
  rescue Exception
    return nil
  end

  def self.egg_steps_for_species(species)
    steps = 0
    begin
      dexdata = pbOpenDexData
      pbDexDataOffset(dexdata, species.to_i, 21)
      steps = dexdata.fgetw
      dexdata.close
    rescue Exception
      begin
        dexdata.close if dexdata
      rescue Exception
      end
    end
    steps = 10240 if steps.to_i <= 0
    return steps.to_i
  rescue Exception
    return 10240
  end

  def self.make_random_trade_egg(species)
    level = defined?(EGGINITIALLEVEL) ? EGGINITIALLEVEL : 1
    pokemon = PokeBattle_Pokemon.new(species.to_i, level, $Trainer)
    pokemon.name = _INTL("Huevo")
    pokemon.eggsteps = egg_steps_for_species(species)
    pokemon.obtainText = _INTL("Intercambio huevo SebiLink")
    pokemon.calcStats if pokemon.respond_to?(:calcStats)
    return pokemon
  rescue Exception
    return nil
  end

  def self.party_has_usable_after_replacing_with_egg(index)
    return false if !$Trainer || !$Trainer.party
    for i in 0...$Trainer.party.length
      next if i == index.to_i
      pokemon = $Trainer.party[i]
      next if !pokemon
      next if pokemon.isEgg?
      return true if pokemon.hp.to_i > 0
    end
    return false
  rescue Exception
    return true
  end

  def self.wonder_trade_daily
    if !$Trainer || !$Trainer.party || $Trainer.party.length == 0
      Kernel.pbMessage(_INTL("No tienes Pokemon en el equipo para intercambiar."))
      return
    end
    index = choose_party_index(_INTL("Elige el Pokemon para el Intercambio prodigio."))
    return if index < 0 || index >= $Trainer.party.length
    original = $Trainer.party[index]
    return if !original
    original_total = base_total_for_species(original.species)
    original_quality = quality_label_for_total(original_total)
    new_species = random_species_for_total(original_total, original.species)
    if !new_species
      Kernel.pbMessage(_INTL("No se pudo encontrar un Pokemon prodigio valido."))
      return
    end
    new_level = original.level.to_i
    new_level = 1 if new_level < 1
    received = PokeBattle_Pokemon.new(new_species, new_level)
    received.setForeignID($Trainer) if received.respond_to?(:setForeignID)
    received.calcStats if received.respond_to?(:calcStats)
    received.heal if received.respond_to?(:heal)
    old_name = original.name
    new_name = PBSpecies.getName(new_species).to_s rescue received.name
    new_total = base_total_for_species(new_species)
    new_quality = quality_label_for_total(new_total)
    Kernel.pbMessage(_INTL("{1} tiene calidad {2} (total stats base: {3}).", old_name, original_quality, original_total))
    return if !Kernel.pbConfirmMessage(_INTL("Intercambiarlo por un Pokemon aleatorio de calidad parecida?"))
    pbStartTrade(index, received, new_name, _INTL("Hombre magico"), 0)
    Kernel.pbMessage(_INTL("Intercambio prodigio completado. Recibiste a {1}, calidad {2} (total stats base: {3}).", new_name, new_quality, new_total))
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo completar el Intercambio prodigio: {1}", $!.message.to_s))
  end

  def self.random_egg_trade_daily
    if !$Trainer || !$Trainer.party || $Trainer.party.length == 0
      Kernel.pbMessage(_INTL("No tienes Pokemon en el equipo para intercambiar."))
      return
    end
    index = choose_party_index(_INTL("Elige el Pokemon que quieres intercambiar por un huevo totalmente aleatorio."))
    return if index < 0 || index >= $Trainer.party.length
    original = $Trainer.party[index]
    return if !original
    if !original.isEgg? && !party_has_usable_after_replacing_with_egg(index)
      Kernel.pbMessage(_INTL("No puedes entregar tu unico Pokemon capaz de combatir para recibir un huevo."))
      return
    end
    return if !Kernel.pbConfirmMessage(_INTL("Recibiras un huevo de una especie completamente aleatoria. Continuar?"))
    new_species = random_any_species
    if !new_species
      Kernel.pbMessage(_INTL("No se pudo encontrar una especie aleatoria valida."))
      return
    end
    received = make_random_trade_egg(new_species)
    if !received
      Kernel.pbMessage(_INTL("No se pudo crear el huevo aleatorio."))
      return
    end
    pbStartTrade(index, received, _INTL("Huevo"), _INTL("Don Huevo"), 0)
    egg = $Trainer.party[index] rescue nil
    if egg
      egg.name = _INTL("Huevo")
      egg.eggsteps = [egg.eggsteps.to_i, 1].max
      egg.obtainText = _INTL("Intercambio huevo SebiLink") if egg.respond_to?(:obtainText=)
      egg.calcStats if egg.respond_to?(:calcStats)
    end
    Kernel.pbMessage(_INTL("Intercambio completado. Recibiste un huevo completamente aleatorio."))
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo completar el Intercambio huevo aleatorio: {1}", $!.message.to_s))
  end

  def self.player_training_level
    level = 1
    if $Trainer && $Trainer.party
      for pokemon in $Trainer.party
        next if !pokemon
        level = pokemon.level.to_i if pokemon.level.to_i > level
      end
    end
    level = 1 if level < 1
    return level
  rescue Exception
    return 50
  end

  def self.training_pokemon(species_symbol, level)
    id = species_id(species_symbol)
    id = species_id(:BLISSEY) if !id || id.to_i <= 0
    pokemon = PokeBattle_Pokemon.new(id, level)
    if pokemon.respond_to?(:iv) && pokemon.iv
      if pokemon.iv.respond_to?(:fill)
        pokemon.iv.fill(31)
      else
        for i in 0...6
          pokemon.iv[i] = 31
        end
      end
    end
    if pokemon.respond_to?(:ev) && pokemon.ev
      if pokemon.ev.respond_to?(:fill)
        pokemon.ev.fill(0)
      else
        for i in 0...6
          pokemon.ev[i] = 0
        end
      end
    end
    pokemon.natureflag = 0 if pokemon.respond_to?(:natureflag=)
    splash = move_id(:SPLASH)
    if splash && splash.to_i > 0 && defined?(PBMove)
      for i in 0...4
        pokemon.moves[i] = PBMove.new(splash)
      end
    end
    pokemon.calcStats if pokemon.respond_to?(:calcStats)
    pokemon.heal if pokemon.respond_to?(:heal)
    return pokemon
  rescue Exception
    return nil
  end

  def self.training_options
    return TRAINING_OPTIONS
  rescue Exception
    return [[:WOBBUFFET, "Wobbuffet", 58], [:CELEBI, "Celebi", 100], [:ARCEUS, "Arceus", 120]]
  end

  def self.choose_training_species
    commands = []
    options = training_options
    for option in options
      commands.push(_INTL("{1} - Def/DefEsp {2}", option[1].to_s, option[2].to_i))
    end
    commands.push(_INTL("Cancelar"))
    default_index = 0
    saved = SebiLinkFileConfig.get("training_species", "WOBBUFFET")
    options.each_with_index { |option, index| default_index = index if option[0].to_s == saved }
    cmd = Kernel.pbMessage(_INTL("Elige Pokemon rival de entrenamiento"), commands, commands.length, nil, default_index)
    return nil if cmd < 0 || cmd >= options.length
    SebiLinkFileConfig.set("training_species", options[cmd][0].to_s)
    return options[cmd]
  rescue Exception
    return nil
  end

  def self.training_party(level, species_symbol)
    party = []
    while party.length < 6
      pokemon = training_pokemon(species_symbol || :WOBBUFFET, level)
      break if !pokemon
      party.push(pokemon)
    end
    return party
  end

  def self.choose_training_mode
    commands = [
      _INTL("Dummies defensivos que no atacan"),
      _INTL("Equipo guardado Showdown"),
      _INTL("Gestionar equipos guardados"),
      _INTL("Cancelar")
    ]
    default_index = SebiLinkFileConfig.get("training_mode", "dummy") == "saved" ? 1 : 0
    cmd = Kernel.pbMessage(_INTL("Entrenamiento SebiLink"), commands, commands.length, nil, default_index)
    if cmd == 0 || cmd == 1
      mode = cmd == 0 ? "dummy" : "saved"
      SebiLinkFileConfig.set("training_mode", mode)
      return mode
    end
    if cmd == 2
      SebiSavedTeams.open_manager if defined?(SebiSavedTeams)
      return choose_training_mode
    end
    return nil
  rescue Exception
    return nil
  end

  def self.saved_training_party
    return [nil, nil, _INTL("Equipos guardados no esta disponible.")] if !defined?(SebiSavedTeams)
    team = SebiSavedTeams.choose_team(_INTL("Elige equipo rival guardado."), SebiLinkFileConfig.get("training_saved_team", ""))
    return [nil, nil, nil] if !team
    SebiLinkFileConfig.set("training_saved_team", team["name"].to_s)
    default_index = SebiLinkFileConfig.get_bool("training_use_attacks", false) ? 0 : 1
    attacks = Kernel.pbMessage(_INTL("Quieres que el entrenador use los ataques reales de ese equipo?"), [_INTL("Si"), _INTL("No")], 2, nil, default_index) == 0
    SebiLinkFileConfig.set("training_use_attacks", attacks)
    party, error = SebiSavedTeams.party_from_team(team, !attacks)
    return [party, team, error]
  rescue Exception
    return [nil, nil, _INTL("No se pudo cargar el equipo guardado.")]
  end

  def self.start_training_battle
    if !$Trainer || !$Trainer.party || $Trainer.pokemonCount == 0
      Kernel.pbMessage(_INTL("Necesitas Pokemon para entrenar."))
      return
    end
    mode = choose_training_mode
    return if !mode
    level = player_training_level
    party = []
    label = ""
    attacks = false
    if mode == "dummy"
      option = choose_training_species
      return if !option
      party = training_party(level, option[0])
      label = _INTL("6 {1} al nivel {2}", option[1].to_s, level)
      attacks = false
    else
      team_party, team, error = saved_training_party
      if error
        Kernel.pbMessage(error)
        return
      end
      return if !team_party
      party = team_party
      label = _INTL("equipo guardado '{1}'", team["name"].to_s)
      attacks = true
      first = party[0] rescue nil
      attacks = false if first && first.moves && first.moves[0] && (first.moves[0].id.to_i rescue 0) == (defined?(SebiSavedTeams) ? SebiSavedTeams.no_damage_move_id : 0)
    end
    if party.length == 0
      Kernel.pbMessage(_INTL("No se pudo preparar el equipo de entrenamiento."))
      return
    end
    if attacks
      Kernel.pbMessage(_INTL("Entrenamiento SebiLink: el rival usara {1} y atacara con sus movimientos.", label))
    else
      Kernel.pbMessage(_INTL("Entrenamiento SebiLink: el rival usara {1}. No tendra movimientos de dano.", label))
    end
    opponent = PokeBattle_Trainer.new(_INTL("Entrenamiento SebiLink"), ($Trainer.trainertype rescue 0))
    opponent.setForeignID($Trainer) if opponent.respond_to?(:setForeignID)
    opponent.party = party
    local_party_backup = Marshal.dump($Trainer.party)
    local_money_backup = $Trainer.money
    decision = 0
    scene = pbNewBattleScene
    battle = PokeBattle_Battle.new(scene, $Trainer.party, party, $Trainer, opponent)
    battle.fullparty1 = false
    battle.fullparty2 = false
    battle.doublebattle = false
    battle.internalbattle = false
    battle.endspeech = _INTL("Entrenamiento terminado.")
    battle.instance_variable_set("@sebi_training_battle", true)
    Events.onStartBattle.trigger(nil, nil)
    pbPrepareBattle(battle)
    begin
      pbBattleAnimation(nil, opponent.trainertype, opponent.name) {
        pbSceneStandby {
          decision = battle.pbStartBattle(true)
        }
      }
    rescue Exception
      pbSceneStandby {
        decision = battle.pbStartBattle(true)
      }
    ensure
      begin
        $Trainer.party = Marshal.load(local_party_backup)
        $Trainer.money = local_money_backup
      rescue Exception
      end
      Events.onEndBattle.trigger(nil, decision, true)
      Input.update
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo iniciar el entrenamiento: {1}", $!.message.to_s))
  end
end

module SebiPokeLinkMenu
  def self.open_menu
    open_main_menu
  rescue Exception
    open_main_menu
  end

  def self.open_main_menu
    begin
      SebiVisualMultiplayer.sebilink_menu_open = true if defined?(SebiVisualMultiplayer)
      loop do
        collision_text = "ON"
        collision_text = "OFF" if defined?(SebiLinkOptions) && !SebiLinkOptions.remote_collisions?
        commands = [
          _INTL("Multijugador"),
          _INTL("Centro Pokemon"),
          _INTL("Intercambio prodigio"),
          _INTL("Intercambio huevo aleatorio"),
          _INTL("Entrenamiento"),
          _INTL("Equipos guardados"),
          _INTL("Trucos"),
          _INTL("Colisiones jugadores: {1}", collision_text),
          _INTL("Guardados automaticos"),
          _INTL("Cargar partida"),
          _INTL("Controles"),
          _INTL("Ventana SebiLink F12"),
          _INTL("Randomizador"),
          _INTL("Buscar actualizaciones"),
          _INTL("Salir")
        ]
        cmd = Kernel.pbMessage(_INTL("SebiLink"), commands, commands.length)
        case cmd
        when 0
          SebiVisualMultiplayer.open_main_menu if defined?(SebiVisualMultiplayer)
          break if defined?(SebiVisualMultiplayer) && SebiVisualMultiplayer.consume_close_sebilink_menu?
        when 1
          SebiPokemonCenter.open_menu if defined?(SebiPokemonCenter)
        when 2
          SebiSpecialActions.wonder_trade_daily if defined?(SebiSpecialActions)
        when 3
          SebiSpecialActions.random_egg_trade_daily if defined?(SebiSpecialActions)
        when 4
          SebiSpecialActions.start_training_battle if defined?(SebiSpecialActions)
        when 5
          SebiSavedTeams.open_manager if defined?(SebiSavedTeams)
        when 6
          SebiCheats.open_menu if defined?(SebiCheats)
        when 7
          SebiLinkOptions.toggle_remote_collisions if defined?(SebiLinkOptions)
        when 8
          result = SebiAutoBackups.open_menu if defined?(SebiAutoBackups)
          break if result == :restored || result == :window_opened
        when 9
          if defined?(SebiSaveManager)
            SebiSaveManager.open_window
          elsif defined?(SebiAutoBackups)
            SebiAutoBackups.open_load_menu
          end
          break
        when 10
          SebiExtraControls.open_menu if defined?(SebiExtraControls)
        when 11
          SebiLinkHub.open_window if defined?(SebiLinkHub)
        when 12
          SebiRandomizer.open_menu if defined?(SebiRandomizer)
        when 13
          SebiLinkUpdater.check_now if defined?(SebiLinkUpdater)
        else
          break
        end
      end
    ensure
      SebiVisualMultiplayer.sebilink_menu_open = false if defined?(SebiVisualMultiplayer)
    end
  end
end

if defined?(DP_PauseMenu)
  class DP_PauseMenu
    unless method_defined?(:sebi_pokelink_update_without_close_signal)
      alias sebi_pokelink_update_without_close_signal update

      def update
        ret = sebi_pokelink_update_without_close_signal
        if defined?(SebiVisualMultiplayer) && SebiVisualMultiplayer.consume_close_pause_menu?
          @done = true
          begin
            @sprites.visible = false if @sprites && @sprites.respond_to?(:visible=)
          rescue Exception
          end
        end
        return ret
      end
    end
  end
end

if defined?(PokemonTradeScene)
  class PokemonTradeScene
    unless method_defined?(:sebi_pokelink_pbTrade_without_egg_name_mask)
      alias sebi_pokelink_pbTrade_without_egg_name_mask pbTrade

      def sebi_pokelink_trade_display_name(pokemon)
        return _INTL("Huevo") if pokemon && pokemon.respond_to?(:isEgg?) && pokemon.isEgg?
        return PBSpecies.getName(pokemon.species) if pokemon && defined?(PBSpecies)
        return pokemon.name if pokemon && pokemon.respond_to?(:name)
        return _INTL("Pokemon")
      rescue Exception
        return _INTL("Huevo") if pokemon && pokemon.respond_to?(:isEgg?) && pokemon.isEgg?
        return _INTL("Pokemon")
      end

      def pbScene2
        spriteBall = IconSprite.new(0, 0, @viewport)
        pictureBall = PictureEx.new(0)
        picturePoke = PictureEx.new(0)
        pictureBall.moveVisible(1, true)
        pictureBall.moveName(1, sprintf("Graphics/Pictures/ball%02d", @pokemon2.ballused))
        pictureBall.moveOrigin(1, PictureOrigin::Center)
        pictureBall.moveXY(0, 1, Graphics.width / 2, -32)
        picturePoke.moveVisible(1, false)
        picturePoke.moveOrigin(1, PictureOrigin::Center)
        picturePoke.moveZoom(0, 1, 0)
        picturePoke.moveColor(0, 1, Color.new(31 * 8, 22 * 8, 30 * 8, 255))
        y = Graphics.height - 96 - 16
        delay = picturePoke.totalDuration + 4
        pictureBall.moveXY(15, delay, Graphics.width / 2, y)
        pictureBall.moveSE(pictureBall.totalDuration, "Audio/SE/balldrop")
        pictureBall.moveXY(8, pictureBall.totalDuration + 2, Graphics.width / 2, y - 60)
        pictureBall.moveXY(7, pictureBall.totalDuration + 2, Graphics.width / 2, y)
        pictureBall.moveSE(pictureBall.totalDuration, "Audio/SE/balldrop")
        pictureBall.moveXY(6, pictureBall.totalDuration + 2, Graphics.width / 2, y - 40)
        pictureBall.moveXY(5, pictureBall.totalDuration + 2, Graphics.width / 2, y)
        pictureBall.moveSE(pictureBall.totalDuration, "Audio/SE/balldrop")
        pictureBall.moveXY(4, pictureBall.totalDuration + 2, Graphics.width / 2, y - 20)
        pictureBall.moveXY(3, pictureBall.totalDuration + 2, Graphics.width / 2, y)
        pictureBall.moveSE(pictureBall.totalDuration, "Audio/SE/balldrop")
        picturePoke.moveXY(0, pictureBall.totalDuration, Graphics.width / 2, y)
        delay = pictureBall.totalDuration + 18
        y = (Graphics.height - 96) * 2 / 3
        picturePoke.moveSE(delay, "Audio/SE/recall")
        if !(@pokemon2.respond_to?(:isEgg?) && @pokemon2.isEgg?)
          cry = pbResolveAudioSE(pbCryFile(@pokemon2))
          picturePoke.moveSE(delay, cry) if cry
        end
        pictureBall.moveName(delay, sprintf("Graphics/Pictures/ball%02d_open", @pokemon2.ballused))
        pictureBall.moveVisible(delay + 10, false)
        picturePoke.moveVisible(delay, true)
        picturePoke.moveZoom(15, delay, 100)
        picturePoke.moveXY(15, delay, Graphics.width / 2, y)
        delay = picturePoke.totalDuration
        picturePoke.moveColor(10, delay, Color.new(31 * 8, 22 * 8, 30 * 8, 0))
        pbRunPictures([picturePoke, pictureBall], [@sprites["rsprite2"], spriteBall])
        spriteBall.dispose
      rescue Exception
        begin
          spriteBall.dispose if spriteBall
        rescue Exception
        end
        raise
      end

      def pbTrade
        pbBGMStop()
        pbPlayCry(@pokemon) if !(@pokemon.respond_to?(:isEgg?) && @pokemon.isEgg?)
        speciesname1 = sebi_pokelink_trade_display_name(@pokemon)
        speciesname2 = sebi_pokelink_trade_display_name(@pokemon2)
        Kernel.pbMessageDisplay(@sprites["msgwindow"],
           _ISPRINTF("{1:s}\r\nID: {2:05d}   EO: {3:s}\\wtnp[0]",
           @pokemon.name,@pokemon.publicID,@pokemon.ot)) { pbUpdate }
        Kernel.pbMessageWaitForInput(@sprites["msgwindow"],100,true) { pbUpdate }
        pbPlayDecisionSE()
        pbScene1
        Kernel.pbMessageDisplay(@sprites["msgwindow"],
           _INTL("Por el {2} de {1},\r\n{3} envia a {4}.\1",@trader1,speciesname1,@trader2,speciesname2)) { pbUpdate }
        Kernel.pbMessageDisplay(@sprites["msgwindow"],
           _INTL("{1} se despide de {2}.",@trader2,speciesname2)) { pbUpdate }
        pbScene2
        Kernel.pbMessageDisplay(@sprites["msgwindow"],
           _ISPRINTF("{1:s}\r\nID: {2:05d}   EO: {3:s}\1",
           @pokemon2.name,@pokemon2.publicID,@pokemon2.ot)) { pbUpdate }
        Kernel.pbMessageDisplay(@sprites["msgwindow"],
           _INTL("Cuida bien de {1}!",speciesname2)) { pbUpdate }
      rescue Exception
        sebi_pokelink_pbTrade_without_egg_name_mask
      end
    end
  end
end

class Object
  unless method_defined?(:sebi_cheats_pbGenerateWildPokemon_without_shiny) ||
         private_method_defined?(:sebi_cheats_pbGenerateWildPokemon_without_shiny)
    alias sebi_cheats_pbGenerateWildPokemon_without_shiny pbGenerateWildPokemon

    def pbGenerateWildPokemon(species, level, isroamer = false)
      pokemon = sebi_cheats_pbGenerateWildPokemon_without_shiny(species, level, isroamer)
      SebiCheats.apply_wild_shiny_roll(pokemon, isroamer)
      return pokemon
    end
  end
end

class PokemonEncounters
  unless method_defined?(:sebi_cheats_pbGenerateEncounter_without_repel)
    alias sebi_cheats_pbGenerateEncounter_without_repel pbGenerateEncounter
    alias sebi_cheats_pbEncounteredPokemon_without_repel pbEncounteredPokemon

    def pbGenerateEncounter(enctype)
      return nil if SebiCheats.max_repel?
      return sebi_cheats_pbGenerateEncounter_without_repel(enctype)
    end

    def pbEncounteredPokemon(enctype, tries = 1)
      return nil if SebiCheats.max_repel?
      return sebi_cheats_pbEncounteredPokemon_without_repel(enctype, tries)
    end
  end
end

class PokeBattle_Battle
  unless method_defined?(:sebi_mp_command_phase_without_pvp)
    alias sebi_mp_command_phase_without_pvp pbCommandPhase
    alias sebi_mp_attack_phase_without_pvp pbAttackPhase
    alias sebi_mp_switch_without_pvp pbSwitch
    alias sebi_mp_switch_in_between_without_pvp pbSwitchInBetween

    def pbCommandPhase
      if instance_variable_defined?("@sebi_pvp_session") && @sebi_pvp_session
        return sebi_mp_pvp_command_phase
      end
      return sebi_mp_command_phase_without_pvp
    end

    def pbAttackPhase
      if instance_variable_defined?("@sebi_pvp_session") && @sebi_pvp_session
        srand(SebiVisualMultiplayer.pvp_seed(@sebi_pvp_session[:token], @turncount))
      end
      return sebi_mp_attack_phase_without_pvp
    end

    def pbSwitch(favorDraws=false)
      if instance_variable_defined?("@sebi_pvp_session") && @sebi_pvp_session
        return sebi_mp_pvp_switch(favorDraws)
      end
      return sebi_mp_switch_without_pvp(favorDraws)
    end

    def pbSwitchInBetween(index,lax,cancancel)
      if instance_variable_defined?("@sebi_pvp_session") && @sebi_pvp_session &&
         !@sebi_pvp_local_switch_pick
        return sebi_mp_pvp_switch_in_between(index,lax,cancancel)
      end
      return sebi_mp_switch_in_between_without_pvp(index,lax,cancancel)
    end

    def sebi_mp_pvp_command_phase
      @sebi_pvp_forfeit = false
      @scene.pbBeginCommandPhase
      @scene.pbResetCommandIndices
      for i in 0...4
        @battlers[i].effects[PBEffects::SkipTurn] = false
        if pbCanShowCommands?(i) || @battlers[i].isFainted?
          @choices[i][0] = 0
          @choices[i][1] = 0
          @choices[i][2] = nil
          @choices[i][3] = -1
        end
      end
      for i in 0...2
        for j in 0...@megaEvolution[i].length
          @megaEvolution[i][j] = -1 if @megaEvolution[i][j] >= 0
        end
      end
      local = []
      for i in 0...4
        next if @decision != 0
        next if !pbOwnedByPlayer?(i)
        next if @battlers[i].isFainted?
        next if !pbCanShowCommands?(i)
        local.push(i)
      end
      for i in local
        sebi_mp_choose_local_command(i)
        break if @decision != 0
      end
      if @sebi_pvp_forfeit
        SebiVisualMultiplayer.send_pvp_choices(@sebi_pvp_session, @turncount, SebiVisualMultiplayer.pvp_forfeit_message)
        pbDisplay(_INTL("Te has rendido."))
        return
      end
      encoded = sebi_mp_encode_choices(local)
      SebiVisualMultiplayer.send_pvp_choices(@sebi_pvp_session, @turncount, encoded)
      pbDisplayBrief(_INTL("Esperando al jugador {1}...", @sebi_pvp_session[:remote_name] || _INTL("rival")))
      remote = SebiVisualMultiplayer.wait_for_pvp_choices(@sebi_pvp_session, @turncount)
      begin
        @scene.pbWaitMessage
      rescue Exception
      end
      if !remote
        pbDisplay(_INTL("Se ha perdido la conexion del combate."))
        @decision = 5
        return
      end
      if !sebi_mp_apply_remote_choices(remote)
        pbDisplay(_INTL("No se pudo sincronizar la decision del rival."))
        @decision = 5
        return
      end
    end

    def sebi_mp_choose_local_command(i)
      commandDone = false
      loop do
        cmd = pbCommandMenu(i)
        if cmd == 0
          if pbCanShowFightMenu?(i)
            until commandDone
              index = @scene.pbFightMenu(i)
              break if index < 0
              next if !pbRegisterMove(i, index)
              if @doublebattle
                thismove = @battlers[i].moves[index]
                target = @battlers[i].pbTarget(thismove)
                if target == PBTargets::SingleNonUser
                  target = @scene.pbChooseTarget(i, target)
                  next if target < 0
                  pbRegisterTarget(i, target)
                elsif target == PBTargets::UserOrPartner
                  target = @scene.pbChooseTarget(i, target)
                  next if target < 0 || (target & 1) == 1
                  pbRegisterTarget(i, target)
                end
              end
              commandDone = true
            end
          else
            pbAutoChooseMove(i)
            commandDone = true
          end
        elsif cmd == 1
          pbDisplay(_INTL("Los objetos no se pueden utilizar en combates multijugador."))
        elsif cmd == 2
          pkmn = pbSwitchPlayer(i, false, true)
          commandDone = true if pkmn >= 0 && pbRegisterSwitch(i, pkmn)
        elsif cmd == 3
          if pbDisplayConfirm(_INTL("Quieres rendirte contra {1}?", @sebi_pvp_session[:remote_name] || _INTL("el rival")))
            @sebi_pvp_forfeit = true
            @decision = 2
            commandDone = true
          end
        elsif cmd == -1
          commandDone = false
        end
        break if commandDone
      end
    end

    def sebi_mp_encode_choices(indexes)
      entries = []
      for i in indexes
        side = pbIsOpposing?(i) ? 1 : 0
        owner = pbGetOwnerIndex(i)
        mega = (@megaEvolution[side][owner] == i) ? 1 : 0
        move_id = sebi_mp_choice_move_id(i)
        entries.push([i, @choices[i][0], @choices[i][1], @choices[i][3], mega, move_id].join(","))
      end
      return entries.join(";")
    end

    def sebi_mp_choice_move_id(index)
      begin
        move = @choices[index][2]
        return move.id.to_i if move && move.respond_to?("id")
      rescue Exception
      end
      begin
        move_index = @choices[index][1].to_i
        move = @battlers[index].moves[move_index]
        return move.id.to_i if move && move.respond_to?("id")
      rescue Exception
      end
      return 0
    end

    def sebi_mp_map_remote_index(index)
      return 1 if index == 0
      return 0 if index == 1
      return 3 if index == 2
      return 2 if index == 3
      return index
    end

    def sebi_mp_expected_remote_command_indexes
      indexes = []
      for i in 0...4
        next if pbOwnedByPlayer?(i)
        next if @battlers[i].isFainted?
        next if !pbCanShowCommands?(i)
        indexes.push(i)
      end
      return indexes
    end

    def sebi_mp_resolve_remote_move_index(battler_index, encoded_index, move_id)
      encoded_index = encoded_index.to_i
      move_id = move_id.to_i
      if move_id > 0
        begin
          moves = @battlers[battler_index].moves
          for i in 0...moves.length
            move = moves[i]
            return i if move && move.respond_to?("id") && move.id.to_i == move_id
          end
        rescue Exception
        end
      end
      return encoded_index
    end

    def sebi_mp_mark_remote_choice(applied, battler_index)
      return if !applied
      applied[battler_index] = true
    end

    def sebi_mp_apply_remote_choices(encoded)
      if !encoded || encoded == ""
        return sebi_mp_expected_remote_command_indexes.length == 0
      end
      if encoded == SebiVisualMultiplayer.pvp_forfeit_message
        pbDisplay(_INTL("{1} se ha rendido.", @sebi_pvp_session[:remote_name] || _INTL("El rival")))
        @decision = 1
        return true
      end
      applied = {}
      for entry in encoded.split(";")
        parts = entry.split(",")
        if parts.length < 5
          SebiVisualMultiplayer.log("invalid pvp choice packet: " + entry.to_s)
          return false
        end
        remote_index = parts[0].to_i
        i = sebi_mp_map_remote_index(remote_index)
        if i < 0 || i >= 4 || pbOwnedByPlayer?(i)
          SebiVisualMultiplayer.log("invalid pvp battler index: " + remote_index.to_s)
          return false
        end
        kind = parts[1].to_i
        arg = parts[2].to_i
        target = sebi_mp_map_remote_index(parts[3].to_i)
        mega = parts[4].to_i
        move_id = (parts.length >= 6) ? parts[5].to_i : 0
        begin
          pbRegisterMegaEvolution(i) if mega == 1
        rescue Exception
        end
        if kind == 1
          move_index = sebi_mp_resolve_remote_move_index(i, arg, move_id)
          if !pbRegisterMove(i, move_index, false)
            SebiVisualMultiplayer.log("invalid pvp move choice: battler=" + i.to_s + " move_index=" + move_index.to_s + " move_id=" + move_id.to_s)
            return false
          end
          pbRegisterTarget(i, target) if target >= 0
          sebi_mp_mark_remote_choice(applied, i)
        elsif kind == 2
          if !pbRegisterSwitch(i, arg)
            SebiVisualMultiplayer.log("invalid pvp switch choice: battler=" + i.to_s + " party_index=" + arg.to_s)
            return false
          end
          sebi_mp_mark_remote_choice(applied, i)
        elsif kind == 5
          @choices[i][0] = 5
          @choices[i][1] = 0
          @choices[i][2] = nil
          @choices[i][3] = -1
          sebi_mp_mark_remote_choice(applied, i)
        else
          SebiVisualMultiplayer.log("unknown pvp choice kind: " + kind.to_s)
          return false
        end
      end
      for i in sebi_mp_expected_remote_command_indexes
        if !applied[i]
          SebiVisualMultiplayer.log("missing pvp remote choice for battler " + i.to_s)
          return false
        end
      end
      return true
    end

    def sebi_mp_pvp_switch(favorDraws=false)
      if !favorDraws
        return if @decision > 0
      else
        return if @decision == 5
      end
      pbJudge()
      return if @decision > 0
      switched = []
      for index in sebi_mp_forced_switch_order
        next if !sebi_mp_forced_switch_needed?(index)
        key = @turncount.to_s + ":forced:" + sebi_mp_canonical_switch_key(index)
        if pbOwnedByPlayer?(index)
          newpoke = sebi_mp_choose_and_send_local_switch(index,key,true,false)
        else
          newpoke = sebi_mp_wait_remote_switch(index,key,true)
        end
        return if @decision > 0
        return if newpoke == nil || newpoke < 0
        newpokename = sebi_mp_switch_display_index(index,newpoke)
        pbRecallAndReplace(index,newpoke,newpokename,false,false)
        switched.push(index)
      end
      if switched.length > 0
        priority = pbPriority
        for i in priority
          i.pbAbilitiesOnSwitchIn(true) if switched.include?(i.index)
        end
      end
    end

    def sebi_mp_pvp_switch_in_between(index,lax,cancancel)
      key = sebi_mp_next_switch_packet_key("between")
      if pbOwnedByPlayer?(index)
        return sebi_mp_choose_and_send_local_switch(index,key,lax,cancancel)
      end
      return sebi_mp_wait_remote_switch(index,key,lax)
    end

    def sebi_mp_forced_switch_order
      indexes = []
      for index in 0...4
        next if !@doublebattle && pbIsDoubleBattler?(index)
        indexes.push(index)
      end
      return indexes.sort_by { |idx| sebi_mp_canonical_battler_key(idx) }
    end

    def sebi_mp_forced_switch_needed?(index)
      return false if !@doublebattle && pbIsDoubleBattler?(index)
      return false if @battlers[index] && !@battlers[index].isFainted?
      return false if !pbCanChooseNonActive?(index)
      return true
    rescue Exception
      return false
    end

    def sebi_mp_canonical_switch_key(index)
      key = sebi_mp_canonical_battler_key(index)
      return key[0].to_s + ":" + key[1].to_s
    rescue Exception
      return index.to_s
    end

    def sebi_mp_next_switch_packet_key(context)
      @sebi_pvp_switch_serial = 0 if !@sebi_pvp_switch_serial
      @sebi_pvp_switch_serial += 1
      return @turncount.to_s + ":" + context.to_s + ":" + @sebi_pvp_switch_serial.to_s
    end

    def sebi_mp_choose_and_send_local_switch(index,key,lax,cancancel)
      @sebi_pvp_local_switch_pick = true
      begin
        newpoke = sebi_mp_switch_in_between_without_pvp(index,lax,cancancel)
      ensure
        @sebi_pvp_local_switch_pick = false
      end
      if newpoke == nil || newpoke < 0
        SebiVisualMultiplayer.send_pvp_switches(@sebi_pvp_session,key,"CANCEL")
        @decision = 5
        return -1
      end
      if !sebi_mp_valid_switch_choice(index,newpoke,lax)
        SebiVisualMultiplayer.log("invalid local pvp switch: battler=" + index.to_s + " party_index=" + newpoke.to_s)
        SebiVisualMultiplayer.send_pvp_switches(@sebi_pvp_session,key,"CANCEL")
        pbDisplay(_INTL("No se pudo sincronizar el cambio local."))
        @decision = 5
        return -1
      end
      SebiVisualMultiplayer.send_pvp_switches(
        @sebi_pvp_session,
        key,
        sebi_mp_encode_switch_entries([[index,newpoke]])
      )
      return newpoke
    end

    def sebi_mp_wait_remote_switch(index,key,lax)
      pbDisplayBrief(_INTL("Esperando cambio de {1}...", @sebi_pvp_session[:remote_name] || _INTL("rival")))
      remote = SebiVisualMultiplayer.wait_for_pvp_switches(@sebi_pvp_session,key)
      begin
        @scene.pbWaitMessage
      rescue Exception
      end
      if !remote || remote == "CANCEL"
        pbDisplay(_INTL("Se ha perdido la sincronizacion del cambio rival."))
        @decision = 5
        return sebi_mp_first_valid_switch(index,lax)
      end
      entries = sebi_mp_decode_switch_entries(remote,true)
      if !sebi_mp_validate_switch_entries(entries,[index],lax)
        SebiVisualMultiplayer.log("invalid pvp switch packet: " + remote.to_s)
        pbDisplay(_INTL("No se pudo sincronizar el cambio rival."))
        @decision = 5
        return sebi_mp_first_valid_switch(index,lax)
      end
      return entries[0][1]
    end

    def sebi_mp_encode_switch_entries(entries)
      encoded = []
      for entry in entries
        encoded.push([entry[0].to_i,entry[1].to_i].join(","))
      end
      return encoded.join(";")
    end

    def sebi_mp_decode_switch_entries(encoded,map_remote=false)
      return [] if !encoded || encoded == ""
      entries = []
      for entry in encoded.split(";")
        next if entry == ""
        parts = entry.split(",")
        return nil if parts.length < 2
        index = parts[0].to_i
        index = sebi_mp_map_remote_index(index) if map_remote
        entries.push([index,parts[1].to_i])
      end
      return entries
    rescue Exception
      return nil
    end

    def sebi_mp_validate_switch_entries(entries,expected_indexes,lax)
      return false if !entries
      expected = {}
      for index in expected_indexes
        expected[index] = true
      end
      seen_indexes = {}
      seen_party = {}
      for entry in entries
        index = entry[0].to_i
        newpoke = entry[1].to_i
        return false if !expected[index]
        return false if seen_indexes[index]
        return false if !sebi_mp_valid_switch_choice(index,newpoke,lax)
        party_key = sebi_mp_switch_party_key(index) + ":" + newpoke.to_s
        return false if seen_party[party_key]
        seen_indexes[index] = true
        seen_party[party_key] = true
      end
      for index in expected_indexes
        return false if !seen_indexes[index]
      end
      return true
    rescue Exception
      return false
    end

    def sebi_mp_valid_switch_choice(index,newpoke,lax)
      return false if newpoke == nil || newpoke < 0
      return pbCanSwitchLax?(index,newpoke,false) if lax
      return pbCanSwitch?(index,newpoke,false)
    rescue Exception
      return false
    end

    def sebi_mp_switch_party_key(index)
      side = pbIsOpposing?(index) ? 1 : 0
      owner = pbGetOwnerIndex(index)
      return side.to_s + ":" + owner.to_s
    rescue Exception
      return index.to_s
    end

    def sebi_mp_switch_display_index(index,newpoke)
      newpokename = newpoke
      if isConst?(pbParty(index)[newpoke].ability,PBAbilities,:ILLUSION)
        newpokename = pbGetLastPokeInTeam(index)
      end
      return newpokename
    rescue Exception
      return newpoke
    end

    def sebi_mp_first_valid_switch(index,lax)
      party = pbParty(index)
      for i in 0...party.length
        return i if sebi_mp_valid_switch_choice(index,i,lax)
      end
      return -1
    rescue Exception
      return -1
    end
  end
end

class PokeBattle_Battle
  unless method_defined?(:sebi_mp_priority_without_pvp_tiebreak)
    alias sebi_mp_priority_without_pvp_tiebreak pbPriority

    def pbPriority(ignorequickclaw = false, log = false)
      priority = sebi_mp_priority_without_pvp_tiebreak(ignorequickclaw, log)
      return priority if !instance_variable_defined?("@sebi_pvp_session") || !@sebi_pvp_session
      return sebi_mp_normalize_pvp_priority(priority)
    end

    def sebi_mp_choice_priority(index)
      pri = 0
      if @choices[index][0] == 1 && @choices[index][2]
        move = @choices[index][2]
        pri = move.priority
        pri += 1 if @field.effects[PBEffects::GrassyTerrain] > 0 && move.function == 0x211
        pri += 1 if @field.effects[PBEffects::MistyTerrain] > 0 && move.function == 0x208
        pri += 1 if @battlers[index].hasWorkingAbility(:PRANKSTER) && move.pbIsStatus?
        pri += 1 if @battlers[index].hasWorkingAbility(:GALEWINGS) && isConst?(move.type, PBTypes, :FLYING)
        pri += 3 if @battlers[index].hasWorkingAbility(:TRIAGE) &&
                    move.isHealingMove? &&
                    !isConst?(move.id, PBMoves, :AQUARING) &&
                    !isConst?(move.id, PBMoves, :GRASSYTERRAIN) &&
                    !isConst?(move.id, PBMoves, :INGRAIN) &&
                    !isConst?(move.id, PBMoves, :LEECHSEED) &&
                    !isConst?(move.id, PBMoves, :PAINSPLIT) &&
                    !isConst?(move.id, PBMoves, :PRESENT)
      end
      return pri
    rescue Exception
      return 0
    end

    def sebi_mp_priority_bucket(battler)
      return nil if !battler
      return [@choices[battler.index][0], sebi_mp_choice_priority(battler.index), battler.pbSpeed]
    rescue Exception
      return nil
    end

    def sebi_mp_priority_item_tie?(battler)
      return false if !battler
      return true if battler.hasWorkingItem(:QUICKCLAW)
      return true if battler.hasWorkingItem(:CUSTAPBERRY)
      return true if battler.hasWorkingItem(:LAGGINGTAIL)
      return true if battler.hasWorkingItem(:FULLINCENSE)
      return true if battler.hasWorkingAbility(:STALL)
      return false
    rescue Exception
      return false
    end

    def sebi_mp_canonical_battler_key(index)
      role = @sebi_pvp_session[:role].to_s
      local_side = ((index & 1) == 0)
      slot = (index / 2).floor
      canonical_side = 0
      if role == "requester"
        canonical_side = local_side ? 0 : 1
      else
        canonical_side = local_side ? 1 : 0
      end
      seed = SebiVisualMultiplayer.pvp_seed(@sebi_pvp_session[:token], @turncount)
      side_order = ((seed & 1) == 0) ? canonical_side : 1 - canonical_side
      return [side_order, slot]
    rescue Exception
      return [index & 1, (index / 2).floor]
    end

    def sebi_mp_normalize_pvp_priority(priority)
      return priority if !priority || priority.length <= 1
      start = 0
      while start < priority.length
        bucket = sebi_mp_priority_bucket(priority[start])
        finish = start + 1
        while finish < priority.length && sebi_mp_priority_bucket(priority[finish]) == bucket
          finish += 1
        end
        if finish - start > 1
          group = priority[start...finish]
          has_item_tie = false
          for battler in group
            has_item_tie = true if sebi_mp_priority_item_tie?(battler)
          end
          if !has_item_tie
            sorted = group.sort_by { |battler| sebi_mp_canonical_battler_key(battler.index) }
            for i in 0...sorted.length
              priority[start + i] = sorted[i]
            end
          end
        end
        start = finish
      end
      return priority
    rescue Exception
      return priority
    end
  end
end

module SebiBattleEffectiveness
  @fight_battle = nil
  @fight_index = nil
  @summary_battle = nil
  @summary_index = nil
  @summary_target_pokemon = nil

  def self.set_fight_context(battle, index)
    @fight_battle = battle
    @fight_index = index
  end

  def self.clear_fight_context
    @fight_battle = nil
    @fight_index = nil
  end

  def self.fight_context
    return nil if !@fight_battle || @fight_index == nil
    return [@fight_battle, @fight_index]
  end

  def self.set_summary_context(battle, index, target_pokemon = nil)
    @summary_battle = battle
    @summary_index = index
    @summary_target_pokemon = target_pokemon
  end

  def self.clear_summary_context
    @summary_battle = nil
    @summary_index = nil
    @summary_target_pokemon = nil
  end

  def self.summary_context
    return nil if !@summary_battle || @summary_index == nil
    return [@summary_battle, @summary_index]
  end

  def self.type_const?(type, name)
    begin
      return hasConst?(PBTypes, name) && isConst?(type, PBTypes, name)
    rescue Exception
      return false
    end
  end

  def self.battle_move(battle, move)
    return nil if !move
    return move if move.is_a?(PokeBattle_Move)
    return PokeBattle_Move.pbFromPBMove(battle, move)
  rescue Exception
    begin
      return PokeBattle_Move.pbFromPBMove(battle, PBMove.new(move.to_i))
    rescue Exception
      return nil
    end
  end

  def self.dummy_attacker(battle, index, pokemon)
    return nil if !battle || !pokemon || pokemon.isEgg?
    battler = PokeBattle_Battler.new(battle, index)
    battler.pbInitPokemon(pokemon, -1)
    return battler
  rescue Exception
    return nil
  end

  def self.dummy_target(battle, index, pokemon)
    return nil if !battle || !pokemon || pokemon.isEgg?
    battler = PokeBattle_Battler.new(battle, index)
    battler.pbInitPokemon(pokemon, -1)
    return battler
  rescue Exception
    return nil
  end

  def self.summary_target_for(battle, index)
    return nil if !battle || index == nil || !@summary_target_pokemon
    return nil if @summary_battle != battle || @summary_index != index
    target_index = (index.to_i % 2 == 0) ? 1 : 0
    return dummy_target(battle, target_index, @summary_target_pokemon)
  rescue Exception
    return nil
  end

  def self.opponents_for(battle, attacker)
    ret = []
    return ret if !battle || !attacker
    for battler in battle.battlers
      next if !battler
      next if battler.index == attacker.index
      next if battler.isFainted?
      next if !attacker.pbIsOpposing?(battler.index)
      ret.push(battler)
    end
    return ret
  rescue Exception
    return []
  end

  def self.safe_type_modifier(move, attacker, target)
    type = move.pbType(move.type, attacker, target)
    mod = move.pbTypeModifier(type, attacker, target)
    return 0 if type_ability_immunity?(move, type, attacker, target)
    return 0 if airborne_ground_immunity?(move, type, attacker, target)
    return 0 if wonder_guard_immunity?(move, type, mod, attacker, target)
    return mod
  rescue Exception
    begin
      type = move.type
      type3 = target.effects[PBEffects::Type3] || -1
      return PBTypes.getCombinedEffectiveness(type, target.type1, target.type2, type3)
    rescue Exception
      return 8
    end
  end

  def self.type_ability_immunity?(move, type, attacker, target)
    return false if !move || !attacker || !target
    return false if attacker.index == target.index
    return false if attacker.hasMoldBreaker
    return true if target.hasWorkingAbility(:SAPSIPPER) && type_const?(type, :GRASS)
    return true if target.hasWorkingAbility(:CUERPOHORNEADO) && type_const?(type, :FIRE)
    return true if target.hasWorkingAbility(:STORMDRAIN) && type_const?(type, :WATER)
    return true if target.hasWorkingAbility(:DESPIERTALLAMA) && type_const?(type, :FIRE)
    return true if target.hasWorkingAbility(:LIGHTNINGROD) && type_const?(type, :ELECTRIC)
    return true if target.hasWorkingAbility(:MOTORDRIVE) && type_const?(type, :ELECTRIC)
    return true if target.hasWorkingAbility(:DRYSKIN) && type_const?(type, :WATER)
    return true if target.hasWorkingAbility(:VOLTABSORB) && type_const?(type, :ELECTRIC)
    return true if target.hasWorkingAbility(:WATERABSORB) && type_const?(type, :WATER)
    return true if target.hasWorkingAbility(:EARTHEATER) && type_const?(type, :GROUND)
    return true if target.hasWorkingAbility(:FLASHFIRE) && type_const?(type, :FIRE)
    return true if target.hasWorkingAbility(:MAGNETISMO) && type_const?(type, :STEEL)
    return true if target.hasWorkingAbility(:MAGNETISMO) && type_const?(type, :ELECTRIC)
    return true if target.hasWorkingAbility(:BULLETPROOF) && move.isBombMove?
    return false
  rescue Exception
    return false
  end

  def self.airborne_ground_immunity?(move, type, attacker, target)
    return false if !type_const?(type, :GROUND)
    return false if move.function == 0x11C
    return false if target.hasWorkingItem(:RINGTARGET)
    return target.isAirborne?(attacker.hasMoldBreaker)
  rescue Exception
    return false
  end

  def self.wonder_guard_immunity?(move, type, mod, attacker, target)
    return false if type < 0
    return false if attacker.hasMoldBreaker
    return false if !target.hasWorkingAbility(:WONDERGUARD)
    return move.pbIsDamaging? && mod <= 8
  rescue Exception
    return false
  end

  def self.result_for_move(battle, index, move, pokemon = nil)
    return nil if !battle || index == nil || !move
    attacker = pokemon ? dummy_attacker(battle, index, pokemon) : battle.battlers[index]
    return nil if !attacker
    battlemove = battle_move(battle, move)
    return nil if !battlemove || battlemove.id == 0
    if battlemove.pbIsStatus?
      return effect_hash("Estado", "Estado", nil, nil)
    end
    target_override = summary_target_for(battle, index)
    targets = target_override ? [target_override] : opponents_for(battle, attacker)
    return nil if targets.length == 0
    mods = []
    for target in targets
      mods.push(safe_type_modifier(battlemove, attacker, target))
    end
    compact = []
    for mod in mods
      compact.push(mod)
    end
    compact.uniq!
    if compact.length == 1
      return hash_for_mod(compact[0])
    end
    mults = []
    for mod in compact
      mults.push(multiplier_text(mod))
    end
    return effect_hash(mults.join("/"), mults.join("/"), nil, compact)
  rescue Exception
    return nil
  end

  def self.result_for_target(battle, index, move, target_index, pokemon = nil)
    return nil if !battle || index == nil || target_index == nil || !move
    attacker = pokemon ? dummy_attacker(battle, index, pokemon) : battle.battlers[index]
    target = battle.battlers[target_index]
    return nil if !attacker || !target || target.isFainted?
    return nil if !attacker.pbIsOpposing?(target.index)
    battlemove = battle_move(battle, move)
    return nil if !battlemove || battlemove.id == 0
    if battlemove.pbIsStatus?
      return effect_hash("Estado", "Estado", nil, nil)
    end
    return hash_for_mod(safe_type_modifier(battlemove, attacker, target))
  rescue Exception
    return nil
  end

  def self.move_data(move)
    return nil if !move || !move.respond_to?(:id)
    return PBMoveData.new(move.id)
  rescue Exception
    return nil
  end

  def self.power_text(move)
    data = move_data(move)
    return "---" if !data
    power = data.basedamage.to_i
    return "---" if power <= 0
    return "???" if power == 1
    return power.to_s
  rescue Exception
    return "---"
  end

  def self.accuracy_text(move)
    data = move_data(move)
    return "---" if !data
    accuracy = data.accuracy.to_i
    return "---" if accuracy <= 0
    return accuracy.to_s
  rescue Exception
    return "---"
  end

  def self.power_accuracy_text(move)
    return power_text(move) + "/" + accuracy_text(move)
  rescue Exception
    return "---/---"
  end

  def self.category_text(move)
    data = move_data(move)
    return "Estado" if !data
    return "Fisico" if data.category == 0
    return "Especial" if data.category == 1
    return "Estado"
  rescue Exception
    return "Estado"
  end

  def self.category_short_text(move)
    text = category_text(move)
    return "Fis" if text == "Fisico"
    return "Esp" if text == "Especial"
    return "Est"
  rescue Exception
    return "Est"
  end

  def self.draw_selected_move_panel_info(bitmap, move, type_bitmap = nil, category_bitmap = nil)
    return if !bitmap || !move || move.id == 0
    panel_y = FightMenuButtons::UPPERGAP
    old_name = bitmap.font.name
    old_size = bitmap.font.size
    begin
      if type_bitmap
        src = Rect.new(0, move.type * 28, 64, 28)
        dst = Rect.new(398, panel_y + 27, 42, 18)
        bitmap.stretch_blt(dst, type_bitmap, src)
      end
      data = move_data(move)
      if category_bitmap && data
        src = Rect.new(0, data.category * 28, 64, 28)
        dst = Rect.new(452, panel_y + 27, 42, 18)
        bitmap.stretch_blt(dst, category_bitmap, src)
      end
    rescue Exception
    end
    pbSetSmallFont(bitmap)
    base = PokeBattle_SceneConstants::MENUBASECOLOR
    shadow = PokeBattle_SceneConstants::MENUSHADOWCOLOR
    pp_base = PokeBattle_SceneConstants::PPTEXTBASECOLOR
    pp_shadow = PokeBattle_SceneConstants::PPTEXTSHADOWCOLOR
    textpos = []
    if move.totalpp && move.totalpp > 0
      textpos.push([_INTL("{1}/{2}", move.pp, move.totalpp), 419, panel_y + 52, 2, pp_base, pp_shadow])
    else
      textpos.push([_INTL("---"), 419, panel_y + 52, 2, pp_base, pp_shadow])
    end
    bitmap.font.size = [bitmap.font.size - 4, 12].max
    textpos.push([_INTL("{1}", power_accuracy_text(move)), 473, panel_y + 52, 2, base, shadow])
    pbDrawTextPositions(bitmap, textpos)
    bitmap.font.name = old_name
    bitmap.font.size = old_size
  rescue Exception
  end

  def self.update_fight_info_panel(info, battler, index)
    return if !info || !battler || index == nil
    move = battler.moves[index]
    return if !move || move.id == 0
    ctag = shadowctag(PokeBattle_SceneConstants::MENUBASECOLOR,
                      PokeBattle_SceneConstants::MENUSHADOWCOLOR)
    movetype = PBTypes.getName(move.type)
    power = power_accuracy_text(move)
    category = category_text(move)
    if move.totalpp == 0
      info.text = _ISPRINTF("{1:s}PP: ---<br>TIPO/{2:s}<br>POT/{3:s} {4:s}", ctag, movetype, power, category)
    else
      info.text = _ISPRINTF("{1:s}PP: {2: 2d}/{3: 2d}<br>TIPO/{4:s}<br>POT/{5:s} {6:s}",
         ctag, move.pp, move.totalpp, movetype, power, category)
    end
  rescue Exception
  end

  def self.set_target_context(battle, index, move)
    @target_battle = battle
    @target_index = index
    @target_move = move
  end

  def self.clear_target_context
    @target_battle = nil
    @target_index = nil
    @target_move = nil
  end

  def self.target_result_for_battler(battler)
    return nil if !@target_battle || @target_index == nil || !@target_move || !battler
    return nil if !@target_battle.battlers || @target_battle.battlers[battler.index] != battler
    return result_for_target(@target_battle, @target_index, @target_move, battler.index)
  rescue Exception
    return nil
  end

  def self.draw_target_box_name(box, battler)
    return if !box || !battler || !box.bitmap
    result = target_result_for_battler(battler)
    return if !result
    base, shadow = colors(result)
    spritebase = box.instance_variable_get("@spritebaseX")
    spritebase = 16 if spritebase == nil
    old_name = box.bitmap.font.name
    old_size = box.bitmap.font.size
    pbSetSystemFont(box.bitmap)
    pbDrawTextPositions(box.bitmap, [[_INTL("{1}", battler.name), spritebase + 8, 6, false, base, shadow, true]])
    box.bitmap.font.name = old_name
    box.bitmap.font.size = old_size
  rescue Exception
  end

  def self.hash_for_mod(mod)
    if mod == 0
      return effect_hash("No afecta", "No afecta", nil, [mod])
    elsif mod < 8
      return effect_hash("Poco eficaz", "Poco", nil, [mod])
    elsif mod == 8
      return effect_hash("Eficaz", "Eficaz", nil, [mod])
    else
      return effect_hash("Super eficaz", "Super", nil, [mod])
    end
  end

  def self.effect_hash(label, short_label, info, mods)
    return {
      :label => label,
      :short_label => short_label,
      :info => info,
      :mods => mods
    }
  end

  def self.multiplier_text(mod)
    return "x0" if mod == 0
    return "x0.125" if mod == 1
    return "x0.25" if mod == 2
    return "x0.5" if mod == 4
    return "x1" if mod == 8
    return "x2" if mod == 16
    return "x4" if mod == 32
    return "x" + sprintf("%.2f", mod.to_f / 8.0)
  end

  def self.colors(result)
    shadow = Color.new(40, 40, 40)
    return [Color.new(248, 248, 160), shadow] if result && result[:mods] == nil
    mods = result ? result[:mods] : nil
    return [Color.new(248, 248, 248), shadow] if !mods || mods.length == 0
    return [Color.new(248, 216, 72), shadow] if mods.length > 1
    return [Color.new(176, 176, 176), shadow] if mods.include?(0)
    mod = mods[0]
    return [Color.new(32, 80, 232), shadow] if mod >= 32
    return [Color.new(88, 184, 255), shadow] if mod > 8
    return [Color.new(176, 32, 32), shadow] if mod <= 2
    return [Color.new(255, 96, 96), shadow] if mod < 8
    return [Color.new(248, 248, 248), shadow]
  end

  def self.draw_fight_move_name_colors(bitmap, moves, battle, index)
    if (!battle || index == nil)
      context = fight_context
      if context
        battle = context[0]
        index = context[1]
      end
    end
    return if !bitmap || !moves || !battle || index == nil
    old_name = bitmap.font.name
    old_size = bitmap.font.size
    pbSetNarrowFont(bitmap)
    for i in 0...4
      next if !moves[i] || moves[i].id == 0
      result = result_for_move(battle, index, moves[i])
      next if !result
      base, shadow = colors(result)
      x = ((i % 2) == 0) ? 4 : 192
      y = ((i / 2) == 0) ? 6 : 48
      y += FightMenuButtons::UPPERGAP
      pbDrawTextPositions(bitmap, [[_INTL("{1}", moves[i].name), x + 96, y + 8, 2, base, shadow]])
    end
    bitmap.font.name = old_name
    bitmap.font.size = old_size
  rescue Exception
  end

  def self.draw_summary_move_name_colors(bitmap, pokemon, move_to_learn = 0)
    context = summary_context
    return if !context || !bitmap || !pokemon
    battle = context[0]
    index = context[1]
    old_name = bitmap.font.name
    old_size = bitmap.font.size
    pbSetSystemFont(bitmap)
    y_pos = 98
    y_pos -= 76 if move_to_learn != 0
    for i in 0...5
      move_object = nil
      if i == 4
        move_object = PBMove.new(move_to_learn) if move_to_learn != 0
        y_pos += 20
      else
        move_object = pokemon.moves[i]
      end
      if move_object && move_object.id != 0
        result = result_for_move(battle, index, move_object, pokemon)
        if result
          base, shadow = colors(result)
          pbDrawTextPositions(bitmap, [[PBMoves.getName(move_object.id), 316, y_pos, 0, base, shadow]])
        end
      end
      y_pos += 64
    end
    bitmap.font.name = old_name
    bitmap.font.size = old_size
  rescue Exception
  end
end

module SebiBattleTools
  @summary_move_index = nil
  @summary_open = false

  def self.summary_move_index
    return @summary_move_index
  end

  def self.summary_open?
    return @summary_open ? true : false
  end

  def self.open_move_summary(pokemon, move_index)
    return if !pokemon
    @summary_move_index = move_index.to_i
    @summary_open = true
    pbFadeOutIn(99999) do
      scene = PokemonSummaryScene.new
      screen = PokemonSummary.new(scene)
      screen.pbStartScreen([pokemon], 0)
    end
  rescue Exception
    Kernel.pbMessage(_INTL("No se pudo abrir los detalles del movimiento."))
  ensure
    @summary_move_index = nil
    @summary_open = false
  end
end

module SebiBattleWeaknessOverlay
  @visible = false
  @loaded_visibility = false
  @party_visible = false
  @loaded_party_visibility = false
  @party_scene = nil
  @consume_y_frame = -1
  @typebitmap = nil

  def self.load_visibility
    return if @loaded_visibility
    @loaded_visibility = true
    if defined?(SebiLinkFileConfig)
      @visible = SebiLinkFileConfig.get_bool("battle_weakness_overlay", false)
    end
  rescue Exception
    @visible = false if @visible == nil
  end

  def self.load_party_visibility
    return if @loaded_party_visibility
    @loaded_party_visibility = true
    if defined?(SebiLinkFileConfig)
      @party_visible = SebiLinkFileConfig.get_bool("party_weakness_overlay", false)
    end
  rescue Exception
    @party_visible = false if @party_visible == nil
  end

  def self.visible?
    load_visibility
    return @visible ? true : false
  end

  def self.party_visible?
    load_party_visibility
    return @party_visible ? true : false
  end

  def self.in_battle_context?
    return true if $game_temp && ($game_temp.in_battle || $game_temp.battle_calling)
    if defined?(SebiLinkHub) && SebiLinkHub.respond_to?(:in_battle?)
      return true if SebiLinkHub.in_battle?
    end
    return false
  rescue Exception
    return false
  end

  def self.party_scene=(scene)
    @party_scene = scene
  rescue Exception
    @party_scene = nil
  end

  def self.party_scene_active?(scene = nil)
    return false if in_battle_context?
    return false if !@party_scene
    return true if scene == nil
    return @party_scene == scene
  rescue Exception
    return false
  end

  def self.consume_y?
    return @consume_y_frame == Graphics.frame_count
  rescue Exception
    return false
  end

  def self.toggle(scene = nil)
    load_visibility
    @visible = !@visible
    SebiLinkFileConfig.set("battle_weakness_overlay", @visible ? "true" : "false") if defined?(SebiLinkFileConfig)
    @consume_y_frame = Graphics.frame_count
    refresh_scene(scene)
  rescue Exception
  end

  def self.toggle_party(scene = nil)
    load_party_visibility
    @party_visible = !@party_visible
    SebiLinkFileConfig.set("party_weakness_overlay", @party_visible ? "true" : "false") if defined?(SebiLinkFileConfig)
    @consume_y_frame = Graphics.frame_count
    refresh_party_scene(scene || @party_scene)
  rescue Exception
  end

  def self.refresh_party_scene(scene)
    return if !scene || !scene.instance_variable_defined?("@sprites")
    sprites = scene.instance_variable_get("@sprites")
    for i in 0...6
      sprite = sprites["pokemon#{i}"] rescue nil
      next if !sprite || !sprite.respond_to?(:refresh)
      sprite.instance_variable_set("@refreshBitmap", true) if sprite.instance_variable_defined?("@refreshBitmap")
      sprite.refresh
    end
  rescue Exception
  end

  def self.refresh_scene(scene)
    return if !scene || !scene.instance_variable_defined?("@sprites")
    sprites = scene.instance_variable_get("@sprites")
    for i in 0...4
      box = sprites["battlebox#{i}"] rescue nil
      box.refresh if box && box.respond_to?(:refresh)
    end
    draw_scene(scene)
  rescue Exception
  end

  def self.type_bitmap
    @typebitmap = AnimatedBitmap.new(_INTL("Graphics/Pictures/types_ico")) if !@typebitmap
    return @typebitmap.bitmap
  rescue Exception
    return nil
  end

  def self.draw_type_icon(bitmap, sheet, type, x, y, width = 16, height = 18)
    return if !bitmap || !sheet || type.to_i < 0
    source = Rect.new(0, type.to_i * 28, 24, 28)
    target = Rect.new(x.to_i, y.to_i, width.to_i, height.to_i)
    bitmap.stretch_blt(target, sheet, source)
  rescue Exception
  end

  def self.weakness_types(battler)
    ret = []
    return ret if !battler
    type3 = -1
    begin
      type3 = battler.effects[PBEffects::Type3] || -1
    rescue Exception
      type3 = -1
    end
    return weakness_types_for_types(battler.type1, battler.type2, type3)
  rescue Exception
    return []
  end

  def self.weakness_types_for_types(type1, type2, type3 = -1)
    ret = []
    for type in 0..PBTypes.maxValue
      next if PBTypes.isPseudoType?(type)
      mod = PBTypes.getCombinedEffectiveness(type, type1, type2, type3)
      ret.push([type, mod]) if mod > 8
    end
    ret.sort! { |a, b| b[1] == a[1] ? a[0] <=> b[0] : b[1] <=> a[1] }
    return ret
  rescue Exception
    return []
  end

  def self.pokemon_weakness_types(pokemon)
    return [] if !pokemon || pokemon.isEgg?
    type1 = pokemon.type1
    type2 = pokemon.type2
    return weakness_types_for_types(type1, type2, -1)
  rescue Exception
    return []
  end

  def self.flying_type?(type)
    return true if defined?(isConst?) && isConst?(type, PBTypes, :FLYING)
    return true if defined?(PBTypes) && PBTypes.const_defined?(:FLYING) && type == PBTypes::FLYING
    return true if type.to_i == 2
    name = PBTypes.getName(type).to_s.downcase rescue ""
    return name == "volador" || name == "flying"
  rescue Exception
    return false
  end

  def self.bug_type?(type)
    return true if defined?(isConst?) && isConst?(type, PBTypes, :BUG)
    return true if defined?(PBTypes) && PBTypes.const_defined?(:BUG) && type == PBTypes::BUG
    return true if type.to_i == 6
    name = PBTypes.getName(type).to_s.downcase rescue ""
    return name == "bicho" || name == "bug"
  rescue Exception
    return false
  end

  def self.spaced_type?(type)
    return flying_type?(type) || bug_type?(type)
  rescue Exception
    return false
  end

  def self.weakness_step(types, index, base_spacing)
    extra = (index == 0) ? 6 : 0
    return base_spacing + extra
  rescue Exception
    return base_spacing
  end

  def self.draw_box(box, battler)
    return
    return if !visible? || !box || !battler || !box.bitmap
    bitmap = type_bitmap
    return if !bitmap
    types = weakness_types(battler)
    return if types.length == 0
    icon_w = 15
    icon_h = 17
    spacing = 17
    width = box.bitmap.width ? box.bitmap.width : 220
    max_fit = [(width - 10) / spacing, 1].max
    max_icons = [types.length, max_fit].min
    start_y = 2
    opposing = (battler.index % 2) == 1
    for i in 0...max_icons
      type = types[i][0]
      x = opposing ? (4 + i * spacing) : (width - icon_w - 4 - i * spacing)
      draw_type_icon(box.bitmap, bitmap, type, x, start_y, icon_w, icon_h)
    end
  rescue Exception
  end

  def self.overlay_sprite(scene)
    return nil if !scene || !scene.instance_variable_defined?("@sprites")
    sprites = scene.instance_variable_get("@sprites")
    sprite = sprites["sebi_weakness_overlay"]
    if !sprite || sprite.disposed?
      viewport = scene.instance_variable_get("@viewport") rescue nil
      sprite = BitmapSprite.new(Graphics.width, Graphics.height, viewport)
      sprite.z = 99999
      sprites["sebi_weakness_overlay"] = sprite
    end
    return sprite
  rescue Exception
    return nil
  end

  def self.draw_scene(scene)
    sprite = overlay_sprite(scene)
    return if !sprite || !sprite.bitmap
    sprite.bitmap.clear
    sprite.visible = visible?
    return if !visible?
    sprites = scene.instance_variable_get("@sprites") rescue nil
    battle = scene.instance_variable_get("@battle") rescue nil
    bitmap = type_bitmap
    return if !sprites || !battle || !bitmap
    icon_w = 18
    icon_h = 20
    spacing = 20
    margin = 16
    edge_margin = 6
    for i in 0...4
      battler = battle.battlers[i] rescue nil
      next if !battler || battler.isFainted?
      box = sprites["battlebox#{i}"] rescue nil
      next if !box
      types = weakness_types(battler)
      next if types.length == 0
      box_width = (box.bitmap && box.bitmap.width) ? box.bitmap.width : 220
      max_icons = types.length
      opposing = (battler.index % 2) == 1
      y = box.y - icon_h + 8
      y = edge_margin if y < edge_margin
      x = opposing ? (box.x + margin) : (box.x + box_width - margin - icon_w)
      for n in 0...max_icons
        type = types[n][0]
        draw_x = x
        draw_x = edge_margin if draw_x < edge_margin
        draw_x = Graphics.width - icon_w - edge_margin if draw_x + icon_w > Graphics.width - edge_margin
        draw_type_icon(sprite.bitmap, bitmap, type, draw_x, y, icon_w, icon_h)
        step = weakness_step(types, n, spacing)
        x += opposing ? step : -step
      end
    end
  rescue Exception
  end

  def self.draw_party_sprite(sprite, pokemon)
    battle_context = visible? && defined?(SebiBattleEffectiveness) && SebiBattleEffectiveness.summary_context
    party_context = party_visible? && party_scene_active?
    return if !battle_context && !party_context
    return if !sprite || !sprite.bitmap || !pokemon
    bitmap = type_bitmap
    return if !bitmap
    types = pokemon_weakness_types(pokemon)
    return if types.length == 0
    max_icons = [types.length, 8].min
    cols = 4
    gap_x = 1
    gap_y = 1
    start_x = 78
    start_y = 65
    icon_w = 14
    begin
      old_name = sprite.bitmap.font.name
      old_size = sprite.bitmap.font.size
      pbSetSystemFont(sprite.bitmap)
      hp_text = _ISPRINTF("{1: 3d}/{2: 3d}", pokemon.hp, pokemon.totalhp)
      hp_width = sprite.bitmap.text_size(hp_text).width rescue hp_text.length * 10
      right_limit = 224 - hp_width - 12
      available = right_limit - start_x
      icon_w = [[((available - gap_x * (cols - 1)) / cols), 10].max, 14].min if available > 0
      sprite.bitmap.font.name = old_name
      sprite.bitmap.font.size = old_size
    rescue Exception
    end
    icon_h = [[(icon_w * 28 / 24), 12].max, 17].min
    for i in 0...max_icons
      type = types[i][0]
      col = i % cols
      row = i / cols
      draw_type_icon(sprite.bitmap, bitmap, type, start_x + col * (icon_w + gap_x), start_y + row * (icon_h + gap_y), icon_w, icon_h)
    end
  rescue Exception
  end
end

class FightMenuButtons
  unless method_defined?(:sebi_eff_refresh_without_effectiveness)
    alias sebi_move_panel_initialize_without_category_icon initialize
    alias sebi_move_panel_dispose_without_category_icon dispose
    alias sebi_eff_refresh_without_effectiveness refresh

    def initialize(index = 0, moves = nil, viewport = nil)
      begin
        @sebi_move_panel_categorybitmap = AnimatedBitmap.new(_INTL("Graphics/Pictures/category"))
      rescue Exception
        @sebi_move_panel_categorybitmap = nil
      end
      sebi_move_panel_initialize_without_category_icon(index, moves, viewport)
    end

    def dispose
      @sebi_move_panel_categorybitmap.dispose if @sebi_move_panel_categorybitmap
      sebi_move_panel_dispose_without_category_icon
    end

    def sebi_eff_set_context(battle, index)
      @sebi_eff_battle = battle
      @sebi_eff_index = index
    end

    def refresh(index, moves, megaButton)
      return if !moves
      self.bitmap.clear
      pbSetNarrowFont(self.bitmap)
      textpos = []
      for i in 0...4
        next if i == index
        next if moves[i].id == 0
        x = ((i % 2) == 0) ? 4 : 192
        y = ((i / 2) == 0) ? 6 : 48
        y += UPPERGAP
        self.bitmap.blt(x, y, @buttonbitmap.bitmap, Rect.new(0, moves[i].type * 46, 192, 46))
        textpos.push([_INTL("{1}", moves[i].name), x + 96, y + 8, 2,
           PokeBattle_SceneConstants::MENUBASECOLOR, PokeBattle_SceneConstants::MENUSHADOWCOLOR])
      end
      for i in 0...4
        next if i != index
        next if moves[i].id == 0
        x = ((i % 2) == 0) ? 4 : 192
        y = ((i / 2) == 0) ? 6 : 48
        y += UPPERGAP
        self.bitmap.blt(x, y, @buttonbitmap.bitmap, Rect.new(192, moves[i].type * 46, 192, 46))
        textpos.push([_INTL("{1}", moves[i].name), x + 96, y + 8, 2,
           PokeBattle_SceneConstants::MENUBASECOLOR, PokeBattle_SceneConstants::MENUSHADOWCOLOR])
      end
      pbDrawTextPositions(self.bitmap, textpos)
      if megaButton > 0
        self.bitmap.blt(146, 0, @megaevobitmap.bitmap, Rect.new(0, (megaButton - 1) * 46, 96, 46))
      end
      SebiBattleEffectiveness.draw_fight_move_name_colors(self.bitmap, moves, @sebi_eff_battle, @sebi_eff_index)
      type_bitmap = @typebitmap ? @typebitmap.bitmap : nil
      category_bitmap = @sebi_move_panel_categorybitmap ? @sebi_move_panel_categorybitmap.bitmap : nil
      SebiBattleEffectiveness.draw_selected_move_panel_info(self.bitmap, moves[index], type_bitmap, category_bitmap) if moves && moves[index]
    end
  end
end

class FightMenuDisplay
  unless method_defined?(:sebi_eff_refresh_without_effectiveness)
    alias sebi_eff_refresh_without_effectiveness refresh

    def sebi_eff_set_context(battle, index)
      @sebi_eff_battle = battle
      @sebi_eff_index = index
      @buttons.sebi_eff_set_context(battle, index) if @buttons && @buttons.respond_to?(:sebi_eff_set_context)
      refresh if @battler
    end

    def refresh
      battle = @sebi_eff_battle
      index = @sebi_eff_index
      if (!battle || index == nil) && defined?(SebiBattleEffectiveness)
        context = SebiBattleEffectiveness.fight_context
        if context
          battle = context[0]
          index = context[1]
        end
      end
      @buttons.sebi_eff_set_context(battle, index) if @buttons && @buttons.respond_to?(:sebi_eff_set_context)
      sebi_eff_refresh_without_effectiveness
      SebiBattleEffectiveness.update_fight_info_panel(@info, @battler, @index)
    rescue Exception
    end
  end
end

class PokemonDataBox
  unless method_defined?(:sebi_eff_refresh_without_target_colors)
    alias sebi_eff_refresh_without_target_colors refresh

    def refresh
      sebi_eff_refresh_without_target_colors
      SebiBattleEffectiveness.draw_target_box_name(self, @battler)
      SebiBattleWeaknessOverlay.draw_box(self, @battler) if defined?(SebiBattleWeaknessOverlay)
    end
  end
end

class PokeSelectionSprite
  unless method_defined?(:sebi_weakness_refresh_without_icons)
    alias sebi_weakness_refresh_without_icons refresh

    def refresh
      sebi_weakness_refresh_without_icons
      SebiBattleWeaknessOverlay.draw_party_sprite(self, @pokemon) if defined?(SebiBattleWeaknessOverlay)
    end
  end
end

class PokemonScreen_Scene
  unless method_defined?(:sebi_party_weakness_pbStartScene_without_context)
    alias sebi_party_weakness_pbStartScene_without_context pbStartScene
    alias sebi_party_weakness_pbEndScene_without_context pbEndScene
    alias sebi_party_weakness_update_without_toggle update

    def pbStartScene(*args)
      if defined?(SebiBattleWeaknessOverlay) && !SebiBattleWeaknessOverlay.in_battle_context?
        SebiBattleWeaknessOverlay.party_scene = self
      end
      ret = sebi_party_weakness_pbStartScene_without_context(*args)
      SebiBattleWeaknessOverlay.refresh_party_scene(self) if defined?(SebiBattleWeaknessOverlay)
      return ret
    end

    def pbEndScene
      return sebi_party_weakness_pbEndScene_without_context
    ensure
      SebiBattleWeaknessOverlay.party_scene = nil if defined?(SebiBattleWeaknessOverlay)
    end

    def update
      ret = sebi_party_weakness_update_without_toggle
      if defined?(SebiBattleWeaknessOverlay) &&
         SebiBattleWeaknessOverlay.party_scene_active?(self) &&
         defined?(SebiExtraControls) && SebiExtraControls.weakness_trigger?
        SebiBattleWeaknessOverlay.toggle_party(self)
      end
      return ret
    end
  end
end

class PokeBattle_Scene
  unless method_defined?(:sebi_db_pbInputUpdate_without_hotkeys)
    alias sebi_db_pbInputUpdate_without_hotkeys pbInputUpdate

    def pbInputUpdate
      ret = sebi_db_pbInputUpdate_without_hotkeys
      SebiLinkHub.battle_scene = self if defined?(SebiLinkHub)
      SebiBattleWeaknessOverlay.draw_scene(self) if defined?(SebiBattleWeaknessOverlay)
      if defined?(SebiExtraControls) && SebiExtraControls.weakness_trigger?
        SebiBattleWeaknessOverlay.toggle(self) if defined?(SebiBattleWeaknessOverlay)
      elsif defined?(SebiExtraControls) && SebiExtraControls.db_trigger? &&
            defined?(SebiPokemonDB) && SebiPokemonDB.can_open_hotkey?
        SebiPokemonDB.open_pending_or_first_opponent(@battle)
      end
      return ret
    end
  end

  unless method_defined?(:sebi_ai_pbStartBattle_without_scene)
    alias sebi_ai_pbStartBattle_without_scene pbStartBattle
    alias sebi_ai_pbEndBattle_without_scene pbEndBattle

    def pbStartBattle(battle)
      SebiLinkHub.battle_scene = self if defined?(SebiLinkHub)
      return sebi_ai_pbStartBattle_without_scene(battle)
    end

    def pbEndBattle(result)
      ret = sebi_ai_pbEndBattle_without_scene(result)
      SebiLinkHub.battle_scene = nil if defined?(SebiLinkHub)
      return ret
    rescue Exception
      SebiLinkHub.battle_scene = nil if defined?(SebiLinkHub)
      raise
    end
  end

  unless method_defined?(:sebi_eff_pbFightMenu_without_effectiveness)
    alias sebi_eff_pbFightMenu_without_effectiveness pbFightMenu
    alias sebi_eff_pbSwitch_without_effectiveness pbSwitch

    def sebi_controls_refresh_fight_after_secondary(index, cw, battler)
      pbShowWindow(FIGHTBOX)
      pbSelectBattler(index)
      pbRefresh
      cw.battler = battler
      cw.setIndex(cw.index)
    rescue Exception
    end

    def sebi_controls_fight_secondary(index, cw, battler)
      commands = []
      handlers = []
      if defined?(SebiBattleTools)
        commands.push(_INTL("Detalles del movimiento"))
        handlers.push(:summary)
      end
      if defined?(SebiBattleWeaknessOverlay)
        commands.push(_INTL("Debilidades"))
        handlers.push(:weakness)
      end
      if @battle.pbCanMegaEvolve?(index)
        commands.push(_INTL("Megaevolucion"))
        handlers.push(:mega)
      end
      return false if handlers.length == 0
      choice = handlers[0]
      if handlers.length > 1
        commands.push(_INTL("Cancelar"))
        cmd = Kernel.pbMessage(_INTL("Accion secundaria"), commands, commands.length)
        return false if cmd < 0 || cmd >= handlers.length
        choice = handlers[cmd]
      end
      case choice
      when :summary
        pokemon = battler.pokemon rescue nil
        SebiBattleTools.open_move_summary(pokemon, cw.index)
        sebi_controls_refresh_fight_after_secondary(index, cw, battler)
      when :weakness
        SebiBattleWeaknessOverlay.toggle(self)
        sebi_controls_refresh_fight_after_secondary(index, cw, battler)
      when :mega
        @battle.pbRegisterMegaEvolution(index)
        cw.megaButton = 2
        pbPlayDecisionSE()
      end
      return true
    rescue Exception
      return false
    end

    def pbFightMenu(index)
      SebiBattleEffectiveness.set_fight_context(@battle, index) if defined?(SebiBattleEffectiveness)
      if @sprites && @sprites["fightwindow"] && @sprites["fightwindow"].respond_to?(:sebi_eff_set_context)
        @sprites["fightwindow"].sebi_eff_set_context(@battle, index)
      end
      return sebi_eff_pbFightMenu_without_effectiveness(index)
    ensure
      SebiBattleEffectiveness.clear_fight_context if defined?(SebiBattleEffectiveness)
    end

    def pbSwitch(index, lax, cancancel)
      pending_switch = defined?(SebiPokemonDB) && SebiPokemonDB.pending_next_switch?
      target_pokemon = pending_switch ? SebiPokemonDB.pending_next_pokemon_for_switch : nil
      SebiBattleEffectiveness.set_summary_context(@battle, index, target_pokemon) if defined?(SebiBattleEffectiveness)
      return sebi_eff_pbSwitch_without_effectiveness(index, lax, cancancel)
    ensure
      SebiBattleEffectiveness.clear_summary_context if defined?(SebiBattleEffectiveness)
      SebiPokemonDB.clear_pending_next if pending_switch && defined?(SebiPokemonDB)
    end
  end
end

class PokeBattle_Scene
  unless method_defined?(:sebi_eff_pbChooseTarget_without_target_colors)
    alias sebi_eff_pbChooseTarget_without_target_colors pbChooseTarget

    def sebi_eff_refresh_target_boxes
      return if !@sprites
      for i in 0...4
        sprite = @sprites["battlebox#{i}"]
        sprite.refresh if sprite && sprite.respond_to?(:refresh)
      end
    rescue Exception
    end

    def pbChooseTarget(index, targettype)
      move = nil
      begin
        choices = @battle.respond_to?(:choices) ? @battle.choices : @battle.instance_variable_get("@choices")
        move = choices[index][2] if choices && choices[index]
      rescue Exception
        move = nil
      end
      SebiBattleEffectiveness.set_target_context(@battle, index, move)
      sebi_eff_refresh_target_boxes
      return sebi_eff_pbChooseTarget_without_target_colors(index, targettype)
    ensure
      SebiBattleEffectiveness.clear_target_context
      sebi_eff_refresh_target_boxes
    end
  end

  unless method_defined?(:sebi_mp_pbCommandMenu_without_pvp_surrender)
    alias sebi_mp_pbCommandMenu_without_pvp_surrender pbCommandMenu

    def pbCommandMenu(index)
      if @battle && @battle.instance_variable_defined?("@sebi_pvp_session") &&
         @battle.instance_variable_get("@sebi_pvp_session")
        return pbCommandMenuEx(index, [
          _INTL("Que hara {1}?", @battle.battlers[index].name),
          _INTL("Luchar"),
          _INTL("Mochila"),
          _INTL("Pokemon"),
          _INTL("Rendirse"),
          _INTL("Ball")
        ])
      end
      return sebi_mp_pbCommandMenu_without_pvp_surrender(index)
    end
  end
end

class PokeBattle_Battle
  unless method_defined?(:sebi_db_pbDisplayPaused_without_pending_next)
    alias sebi_db_pbDisplayPaused_without_pending_next pbDisplayPaused

    def pbDisplayPaused(msg)
      SebiPokemonDB.capture_pending_next_from_message(self, msg) if defined?(SebiPokemonDB)
      return sebi_db_pbDisplayPaused_without_pending_next(msg)
    end
  end

  unless method_defined?(:sebi_db_pbDisplayConfirm_without_pending_next)
    alias sebi_db_pbDisplayConfirm_without_pending_next pbDisplayConfirm

    def pbDisplayConfirm(msg)
      next_switch_prompt = false
      if defined?(SebiPokemonDB) && SebiPokemonDB.shift_confirm_message?(msg)
        next_switch_prompt = true
        SebiPokemonDB.begin_pending_next_prompt
      end
      ret = sebi_db_pbDisplayConfirm_without_pending_next(msg)
      if next_switch_prompt && defined?(SebiPokemonDB)
        if ret
          SebiPokemonDB.begin_pending_next_switch
        else
          SebiPokemonDB.clear_pending_next
        end
      end
      return ret
    rescue Exception
      SebiPokemonDB.clear_pending_next if next_switch_prompt && defined?(SebiPokemonDB)
      raise
    end
  end
end

class PokeBattle_Battle
  unless method_defined?(:sebi_history_pbCommandPhase_without_history)
    alias sebi_history_pbCommandPhase_without_history pbCommandPhase
    alias sebi_history_pbAttackPhase_without_history pbAttackPhase

    def pbCommandPhase
      ret = sebi_history_pbCommandPhase_without_history
      SebiBattleHistory.record_choices(self) if defined?(SebiBattleHistory)
      SebiBattleSpectator.publish(self, "commands") if defined?(SebiBattleSpectator)
      return ret
    end

    def pbAttackPhase
      ret = sebi_history_pbAttackPhase_without_history
      SebiBattleHistory.record_turn_end(self) if defined?(SebiBattleHistory)
      SebiBattleSpectator.publish(self, "actions") if defined?(SebiBattleSpectator)
      return ret
    end
  end

  if method_defined?(:pbDisplay) && !method_defined?(:sebi_history_pbDisplay_without_history)
    alias sebi_history_pbDisplay_without_history pbDisplay

    def pbDisplay(msg)
      SebiBattleHistory.record_message(self, msg) if defined?(SebiBattleHistory)
      SebiBattleSpectator.publish_throttled(self, "message") if defined?(SebiBattleSpectator)
      return sebi_history_pbDisplay_without_history(msg)
    end
  end

  if method_defined?(:pbDisplayBrief) && !method_defined?(:sebi_history_pbDisplayBrief_without_history)
    alias sebi_history_pbDisplayBrief_without_history pbDisplayBrief

    def pbDisplayBrief(msg)
      SebiBattleHistory.record_message(self, msg) if defined?(SebiBattleHistory)
      SebiBattleSpectator.publish_throttled(self, "message") if defined?(SebiBattleSpectator)
      return sebi_history_pbDisplayBrief_without_history(msg)
    end
  end

  if method_defined?(:pbDisplayPaused) && !method_defined?(:sebi_history_pbDisplayPaused_without_history)
    alias sebi_history_pbDisplayPaused_without_history pbDisplayPaused

    def pbDisplayPaused(msg)
      SebiBattleHistory.record_message(self, msg) if defined?(SebiBattleHistory)
      SebiBattleSpectator.publish_throttled(self, "message") if defined?(SebiBattleSpectator)
      return sebi_history_pbDisplayPaused_without_history(msg)
    end
  end

  if method_defined?(:pbDisplayConfirm) && !method_defined?(:sebi_history_pbDisplayConfirm_without_history)
    alias sebi_history_pbDisplayConfirm_without_history pbDisplayConfirm

    def pbDisplayConfirm(msg)
      SebiBattleHistory.record_message(self, msg) if defined?(SebiBattleHistory)
      SebiBattleSpectator.publish_throttled(self, "message") if defined?(SebiBattleSpectator)
      return sebi_history_pbDisplayConfirm_without_history(msg)
    end
  end
end

class PokeBattle_Scene
  unless method_defined?(:sebi_history_pbStartBattle_without_history)
    alias sebi_history_pbStartBattle_without_history pbStartBattle
    alias sebi_history_pbEndBattle_without_history pbEndBattle

    def pbStartBattle(battle)
      SebiBattleHistory.start(battle) if defined?(SebiBattleHistory)
      SebiBattleSpectator.start(battle) if defined?(SebiBattleSpectator)
      ret = sebi_history_pbStartBattle_without_history(battle)
      SebiBattleSpectator.publish(battle, "start") if defined?(SebiBattleSpectator)
      return ret
    end

    def pbEndBattle(result)
      battle = @battle
      SebiBattleSpectator.finish(battle, result) if battle && defined?(SebiBattleSpectator)
      SebiBattleHistory.finish(battle, result) if battle && defined?(SebiBattleHistory)
      return sebi_history_pbEndBattle_without_history(result)
    end
  end
end

class PokemonScreen_Scene
  unless method_defined?(:sebi_controls_pbChoosePokemon_without_back_action)
    alias sebi_controls_pbChoosePokemon_without_back_action pbChoosePokemon

    def pbChoosePokemon(switching = false, initialsel = -1)
      return sebi_controls_pbChoosePokemon_without_back_action(switching, initialsel)
    end
  end
end

class PokemonSummaryScene
  unless method_defined?(:sebi_save_editor_pbStartScene_without_live_refresh)
    alias sebi_save_editor_pbStartScene_without_live_refresh pbStartScene
    alias sebi_save_editor_pbStartForgetScene_without_live_refresh pbStartForgetScene
    alias sebi_save_editor_pbEndScene_without_live_refresh pbEndScene

    def pbStartScene(*args)
      SebiSaveEditor.current_summary_scene = self if defined?(SebiSaveEditor)
      return sebi_save_editor_pbStartScene_without_live_refresh(*args)
    end

    def pbStartForgetScene(*args)
      SebiSaveEditor.current_summary_scene = self if defined?(SebiSaveEditor)
      return sebi_save_editor_pbStartForgetScene_without_live_refresh(*args)
    end

    def pbEndScene
      return sebi_save_editor_pbEndScene_without_live_refresh
    ensure
      if defined?(SebiSaveEditor) && SebiSaveEditor.current_summary_scene == self
        SebiSaveEditor.current_summary_scene = nil
      end
    end
  end

  unless method_defined?(:sebi_db_pbUpdate_without_hotkey)
    alias sebi_db_pbUpdate_without_hotkey pbUpdate

    def pbUpdate
      SebiPokemonDB.open_hotkey_for_pokemon(@pokemon) if defined?(SebiPokemonDB)
      return sebi_db_pbUpdate_without_hotkey
    end
  end

  unless method_defined?(:sebi_eff_drawPageFour_without_effectiveness)
    alias sebi_eff_drawPageFour_without_effectiveness drawPageFour
    alias sebi_eff_drawMoveSelection_without_effectiveness drawMoveSelection
    alias sebi_eff_drawSelectedMove_without_effectiveness drawSelectedMove

    def drawPageFour(pokemon)
      sebi_eff_drawPageFour_without_effectiveness(pokemon)
      SebiBattleEffectiveness.draw_summary_move_name_colors(@sprites["overlay"].bitmap, pokemon, 0)
    end

    def drawMoveSelection(pokemon, moveToLearn)
      sebi_eff_drawMoveSelection_without_effectiveness(pokemon, moveToLearn)
      SebiBattleEffectiveness.draw_summary_move_name_colors(@sprites["overlay"].bitmap, pokemon, moveToLearn)
    end

    def drawSelectedMove(pokemon, moveToLearn, moveid)
      sebi_eff_drawSelectedMove_without_effectiveness(pokemon, moveToLearn, moveid)
    end
  end

  unless method_defined?(:sebi_battle_tools_pbStartScene_without_move_page)
    alias sebi_battle_tools_pbStartScene_without_move_page pbStartScene

    def pbStartScene(party, partyindex)
      sebi_battle_tools_pbStartScene_without_move_page(party, partyindex)
      if defined?(SebiBattleTools) && SebiBattleTools.summary_move_index != nil
        move_index = SebiBattleTools.summary_move_index
        move_index = 0 if move_index < 0
        move_index = 3 if move_index > 3
        @page = 3
        @sprites["movesel"].visible = true if @sprites["movesel"]
        @sprites["movesel"].index = move_index if @sprites["movesel"]
        drawPageFour(@pokemon)
      end
    end
  end

  unless method_defined?(:sebi_battle_tools_pbScene_without_summary_controls)
    alias sebi_battle_tools_pbScene_without_summary_controls pbScene
    alias sebi_battle_tools_pbMoveSelection_without_summary_controls pbMoveSelection

    def sebi_battle_tools_summary_accept?
      return false if !defined?(SebiBattleTools) || !SebiBattleTools.summary_open?
      return Input.trigger?(Input::C)
    rescue Exception
      return false
    end

    def sebi_battle_tools_summary_back?
      return false if !defined?(SebiBattleTools) || !SebiBattleTools.summary_open?
      return Input.trigger?(Input::B)
    rescue Exception
      return false
    end

    def pbMoveSelection
      return sebi_battle_tools_pbMoveSelection_without_summary_controls if !defined?(SebiBattleTools) || !SebiBattleTools.summary_open?
      @sprites["movesel"].visible = true
      @sprites["movesel"].index = 0
      selmove = 0
      oldselmove = 0
      switching = false
      drawSelectedMove(@pokemon, 0, @pokemon.moves[selmove].id)
      loop do
        Graphics.update
        Input.update
        pbUpdate
        if @sprites["movepresel"].index == @sprites["movesel"].index
          @sprites["movepresel"].z = @sprites["movesel"].z + 1
        else
          @sprites["movepresel"].z = @sprites["movesel"].z
        end
        break if sebi_battle_tools_summary_back?
        if sebi_battle_tools_summary_accept?
          if !(@pokemon.isShadow? rescue false)
            if !switching
              @sprites["movepresel"].index = selmove
              oldselmove = selmove
              @sprites["movepresel"].visible = true
              switching = true
            else
              tmpmove = @pokemon.moves[oldselmove]
              @pokemon.moves[oldselmove] = @pokemon.moves[selmove]
              @pokemon.moves[selmove] = tmpmove
              @sprites["movepresel"].visible = false
              switching = false
              drawSelectedMove(@pokemon, 0, @pokemon.moves[selmove].id)
            end
          end
        end
        if Input.trigger?(Input::DOWN)
          selmove += 1
          selmove = 0 if selmove < 4 && selmove >= @pokemon.numMoves
          selmove = 0 if selmove >= 4
          selmove = 4 if selmove < 0
          @sprites["movesel"].index = selmove
          newmove = @pokemon.moves[selmove].id
          pbPlayCursorSE()
          drawSelectedMove(@pokemon, 0, newmove)
        end
        if Input.trigger?(Input::UP)
          selmove -= 1
          if selmove < 4 && selmove >= @pokemon.numMoves
            selmove = @pokemon.numMoves - 1
          end
          selmove = 0 if selmove >= 4
          selmove = @pokemon.numMoves - 1 if selmove < 0
          @sprites["movesel"].index = selmove
          newmove = @pokemon.moves[selmove].id
          pbPlayCursorSE()
          drawSelectedMove(@pokemon, 0, newmove)
        end
      end
      @sprites["movepresel"].visible = false if @sprites["movepresel"]
      @sprites["movesel"].visible = false
    end

    def pbScene
      return sebi_battle_tools_pbScene_without_summary_controls if !defined?(SebiBattleTools) || !SebiBattleTools.summary_open?
      pbPlayCry(@pokemon)
      loop do
        Graphics.update
        Input.update
        pbUpdate
        break if sebi_battle_tools_summary_back?
        dorefresh = false
        if sebi_battle_tools_summary_accept?
          if @page == 2
            dorefresh = true
            Habilidades(@pokemon)
          elsif @page == 0
            break
          elsif @page == 3
            pbMoveSelection
            dorefresh = true
            drawPageFour(@pokemon)
          end
        end
        if Input.trigger?(Input::UP) && @partyindex > 0
          oldindex = @partyindex
          pbGoToPrevious
          if @partyindex != oldindex
            @pokemon = @party[@partyindex]
            @sprites["pokemon"].setPokemonBitmap(@pokemon)
            @sprites["pokemon"].color = Color.new(0, 0, 0, 0)
            pbPositionPokemonSprite(@sprites["pokemon"], 40, 144)
            dorefresh = true
            pbPlayCry(@pokemon)
          end
        end
        if Input.trigger?(Input::DOWN) && @partyindex < @party.length - 1
          oldindex = @partyindex
          pbGoToNext
          if @partyindex != oldindex
            @pokemon = @party[@partyindex]
            @sprites["pokemon"].setPokemonBitmap(@pokemon)
            @sprites["pokemon"].color = Color.new(0, 0, 0, 0)
            pbPositionPokemonSprite(@sprites["pokemon"], 40, 144)
            dorefresh = true
            pbPlayCry(@pokemon)
          end
        end
        if Input.trigger?(Input::LEFT) && !@pokemon.isEgg?
          oldpage = @page
          @page -= 1
          @page = 0 if @page < 0
          @page = 4 if @page > 4
          if @page != oldpage
            pbPlayCursorSE()
            dorefresh = true
          end
        end
        if Input.trigger?(Input::RIGHT) && !@pokemon.isEgg?
          oldpage = @page
          @page += 1
          @page = 0 if @page < 0
          @page = 4 if @page > 4
          if @page != oldpage
            pbPlayCursorSE()
            dorefresh = true
          end
        end
        if dorefresh
          case @page
          when 0
            drawPageOne(@pokemon)
          when 1
            drawPageTwo(@pokemon)
          when 2
            drawPageThree(@pokemon)
          when 3
            drawPageFour(@pokemon)
          when 4
            drawPageFive(@pokemon)
          end
        end
      end
      return @partyindex
    end
  end
end

if defined?(AdvancedPokedexScene)
  class AdvancedPokedexScene
    unless method_defined?(:sebi_db_pbUpdate_without_hotkey)
      alias sebi_db_pbUpdate_without_hotkey pbUpdate

      def pbUpdate
        SebiPokemonDB.open_hotkey_for_species(@species) if defined?(SebiPokemonDB)
        return sebi_db_pbUpdate_without_hotkey
      end
    end
  end
end

if defined?(MoveRelearnerScene)
  class MoveRelearnerScene
    unless method_defined?(:sebi_db_pbUpdate_without_hotkey)
      alias sebi_db_pbUpdate_without_hotkey pbUpdate

      def pbUpdate
        SebiPokemonDB.open_hotkey_for_pokemon(@pokemon) if defined?(SebiPokemonDB)
        return sebi_db_pbUpdate_without_hotkey
      end
    end
  end
end

module SebiRegionMapPlayers
  @map_dimensions = {}

  def self.palette
    return [
      Color.new(255, 64, 64, 100),
      Color.new(64, 160, 255, 100),
      Color.new(80, 230, 110, 100),
      Color.new(255, 220, 64, 100),
      Color.new(210, 90, 255, 100),
      Color.new(255, 150, 40, 100)
    ]
  rescue Exception
    return []
  end

  def self.map_dimensions(map_id)
    @map_dimensions = {} if !@map_dimensions
    return @map_dimensions[map_id] if @map_dimensions.has_key?(map_id)
    ret = nil
    begin
      filename = sprintf("Data/Map%03d.rxdata", map_id.to_i)
      if FileTest.exist?(filename)
        map = load_data(filename)
        ret = [map.width, map.height] if map && map.respond_to?(:width) && map.respond_to?(:height)
      end
    rescue Exception
      ret = nil
    end
    @map_dimensions[map_id] = ret
    return ret
  end

  def self.map_region(scene)
    mapdata = scene.instance_variable_get("@mapdata") rescue nil
    map = scene.instance_variable_get("@map") rescue nil
    return 0 if !mapdata || !map
    for i in 0...mapdata.length
      return i if mapdata[i] == map
    end
    return 0
  rescue Exception
    return 0
  end

  def self.remote_coords(player, region)
    return nil if !player || !player.respond_to?(:remote_map_id)
    map_id = player.remote_map_id.to_i
    pos = pbGetMetadata(map_id, MetadataMapPosition) rescue nil
    return nil if !pos || pos[0].to_i != region.to_i
    x = pos[1].to_i
    y = pos[2].to_i
    mapsize = pbGetMetadata(map_id, MetadataMapSize) rescue nil
    if mapsize && mapsize[0] && mapsize[0].to_i > 0
      dimensions = map_dimensions(map_id)
      if dimensions && dimensions[0].to_i > 0 && dimensions[1].to_i > 0
        sqwidth = mapsize[0].to_i
        sqheight = (mapsize[1].length * 1.0 / sqwidth).ceil rescue 1
        x += (player.x.to_i * sqwidth / dimensions[0].to_i).floor if sqwidth > 1
        y += (player.y.to_i * sqheight / dimensions[1].to_i).floor if sqheight > 1
      end
    end
    return [x, y]
  rescue Exception
    return nil
  end

  def self.draw(scene)
    return if !defined?(SebiVisualMultiplayer)
    sprites = scene.instance_variable_get("@sprites") rescue nil
    viewport = scene.instance_variable_get("@viewport") rescue nil
    return if !sprites || !viewport || !sprites["map"] || !sprites["map"].bitmap
    clear(scene)
    region = map_region(scene)
    origin_x = sprites["map"].x
    origin_y = sprites["map"].y
    players = SebiVisualMultiplayer.online_players(true)
    colors = palette
    offsets = [[0, 0], [5, 0], [-5, 0], [0, 5], [0, -5], [5, 5], [-5, 5]]
    index = 0
    for player in players
      coords = remote_coords(player, region)
      next if !coords
      sprite = IconSprite.new(0, 0, viewport)
      begin
        sprite.setBitmap(pbPlayerHeadFile($Trainer.trainertype))
      rescue Exception
        sprite.setBitmap(pbPlayerHeadFile(0))
      end
      offset = offsets[index % offsets.length]
      sprite.x = -PokemonRegionMapScene::SQUAREWIDTH / 2 +
                 (coords[0] * PokemonRegionMapScene::SQUAREWIDTH) + origin_x + offset[0]
      sprite.y = -PokemonRegionMapScene::SQUAREHEIGHT / 2 +
                 (coords[1] * PokemonRegionMapScene::SQUAREHEIGHT) + origin_y + offset[1]
      sprite.z = 99999
      sprite.color = colors[index % colors.length] if colors && colors.length > 0
      sprites["sebi_remote_region_player#{index}"] = sprite
      index += 1
    end
    marker_index = 0
    for marker in SebiVisualMultiplayer.shared_markers(region)
      sprite = Sprite.new(viewport)
      sprite.bitmap = Bitmap.new(24, 24)
      color = colors[marker_index % colors.length] rescue Color.new(255, 64, 64)
      solid = Color.new(color.red, color.green, color.blue, 255) rescue Color.new(255, 64, 64)
      edge = Color.new(32, 32, 32, 255)
      sprite.bitmap.fill_rect(10, 1, 4, 22, edge)
      sprite.bitmap.fill_rect(1, 10, 22, 4, edge)
      sprite.bitmap.fill_rect(7, 7, 10, 10, edge)
      sprite.bitmap.fill_rect(11, 2, 2, 20, solid)
      sprite.bitmap.fill_rect(2, 11, 20, 2, solid)
      sprite.bitmap.fill_rect(8, 8, 8, 8, solid)
      sprite.x = origin_x + (marker[:x].to_i * PokemonRegionMapScene::SQUAREWIDTH) +
                 ((PokemonRegionMapScene::SQUAREWIDTH - sprite.bitmap.width) / 2)
      sprite.y = origin_y + (marker[:y].to_i * PokemonRegionMapScene::SQUAREHEIGHT) +
                 ((PokemonRegionMapScene::SQUAREHEIGHT - sprite.bitmap.height) / 2)
      sprite.visible = true
      sprite.z = 200000
      sprites["sebi_room_marker#{marker_index}"] = sprite
      marker_index += 1
    end
    scene.instance_variable_set("@sebi_region_marker_revision", SebiVisualMultiplayer.marker_revision)
    scene.instance_variable_set("@sebi_region_last_draw_frame", (Graphics.frame_count rescue 0))
  rescue Exception
  end

  def self.clear(scene)
    sprites = scene.instance_variable_get("@sprites") rescue nil
    return if !sprites
    for key in sprites.keys
      text = key.to_s
      next if text.index("sebi_remote_region_player") != 0 && text.index("sebi_room_marker") != 0
      sprite = sprites[key]
      begin
        sprite.bitmap.dispose if sprite && sprite.bitmap && text.index("sebi_room_marker") == 0 && !sprite.bitmap.disposed?
      rescue Exception
      end
      begin
        sprite.dispose if sprite && !sprite.disposed?
      rescue Exception
      end
      sprites.delete(key)
    end
  rescue Exception
  end

  def self.refresh_if_needed(scene)
    revision = scene.instance_variable_get("@sebi_region_marker_revision") rescue -1
    last_frame = scene.instance_variable_get("@sebi_region_last_draw_frame") rescue -9999
    frame = Graphics.frame_count rescue 0
    if revision.to_i != SebiVisualMultiplayer.marker_revision.to_i || frame - last_frame.to_i >= 30
      draw(scene)
    end
  rescue Exception
  end

  def self.marker_x_triggered?(scene)
    triggered = false
    pressed = false
    if defined?(SebiControls)
      triggered = true if SebiControls.button_x_trigger?
      begin
        triggered = true if !triggered && SebiControls.action_trigger?(SebiControls::ACTION_BAG)
      rescue Exception
      end
      begin
        pressed = true if SebiControls.action_press?(SebiControls::ACTION_BAG)
      rescue Exception
      end
    end
    begin
      triggered = true if !triggered && Input.trigger?(Input::X)
    rescue Exception
    end
    begin
      pressed = true if Input.press?(Input::X)
    rescue Exception
    end
    was_pressed = scene.instance_variable_get("@sebi_region_marker_x_pressed") rescue false
    scene.instance_variable_set("@sebi_region_marker_x_pressed", pressed)
    return true if triggered
    return pressed && !was_pressed
  rescue Exception
    return false
  end

  def self.handle_marker_input(scene, mode = nil)
    return if !defined?(SebiVisualMultiplayer)
    mode = scene.instance_variable_get("@sebi_region_mode") if mode == nil
    aseditor = scene.instance_variable_get("@sebi_region_aseditor") rescue false
    return if aseditor
    frame = Graphics.frame_count rescue 0
    last_frame = scene.instance_variable_get("@sebi_region_marker_input_frame") rescue -9999
    return if last_frame.to_i == frame.to_i
    return if !marker_x_triggered?(scene)
    scene.instance_variable_set("@sebi_region_marker_input_frame", frame)
    x = scene.instance_variable_get("@mapX") rescue nil
    y = scene.instance_variable_get("@mapY") rescue nil
    return if x == nil || y == nil
    SebiVisualMultiplayer.toggle_shared_marker(map_region(scene), x.to_i, y.to_i, false)
    pbPlayDecisionSE() if defined?(pbPlayDecisionSE)
    draw(scene)
  rescue Exception
  end

  def self.map_multiplayer_a_pressed?
    pressed = false
    if defined?(SebiControls)
      begin
        pressed = true if SebiControls.action_press?(SebiControls::ACTION_RUN_TOGGLE)
      rescue Exception
      end
    end
    begin
      pressed = true if Input.press?(Input::A)
    rescue Exception
    end
    return pressed
  rescue Exception
    return false
  end

  def self.map_multiplayer_a_triggered?(scene)
    triggered = false
    pressed = map_multiplayer_a_pressed?
    if defined?(SebiControls)
      begin
        triggered = true if SebiControls.action_trigger?(SebiControls::ACTION_RUN_TOGGLE)
      rescue Exception
      end
    end
    begin
      triggered = true if !triggered && Input.trigger?(Input::A)
    rescue Exception
    end
    was_pressed = scene.instance_variable_get("@sebi_region_multiplayer_a_pressed") rescue false
    scene.instance_variable_set("@sebi_region_multiplayer_a_pressed", pressed)
    return true if triggered
    return pressed && !was_pressed
  rescue Exception
    return false
  end

  def self.handle_multiplayer_menu_input(scene, mode = nil)
    return false if !defined?(SebiVisualMultiplayer)
    mode = scene.instance_variable_get("@sebi_region_mode") if mode == nil
    aseditor = scene.instance_variable_get("@sebi_region_aseditor") rescue false
    return false if aseditor
    frame = Graphics.frame_count rescue 0
    last_frame = scene.instance_variable_get("@sebi_region_multiplayer_input_frame") rescue -9999
    return false if frame - last_frame.to_i < 12
    return false if !map_multiplayer_a_triggered?(scene)
    scene.instance_variable_set("@sebi_region_multiplayer_input_frame", frame)
    pbPlayDecisionSE() if defined?(pbPlayDecisionSE)
    SebiVisualMultiplayer.open_main_menu
    draw(scene)
    return true
  rescue Exception
    return false
  end
end

if defined?(PokemonRegionMapScene)
  class PokemonRegionMapScene
    unless method_defined?(:sebi_region_map_pbStartScene_without_remote_players)
      alias sebi_region_map_pbStartScene_without_remote_players pbStartScene

      def pbStartScene(aseditor = false, mode = 0)
        @sebi_region_aseditor = aseditor
        @sebi_region_mode = mode
        ret = sebi_region_map_pbStartScene_without_remote_players(aseditor, mode)
        begin
          @sebi_region_multiplayer_a_pressed = SebiRegionMapPlayers.map_multiplayer_a_pressed? if defined?(SebiRegionMapPlayers)
          @sebi_region_multiplayer_input_frame = Graphics.frame_count
        rescue Exception
        end
        SebiRegionMapPlayers.draw(self) if ret && defined?(SebiRegionMapPlayers)
        return ret
      end
    end

    if method_defined?(:pbUpdate) && !method_defined?(:sebi_region_map_pbUpdate_without_shared_markers)
      alias sebi_region_map_pbUpdate_without_shared_markers pbUpdate

      def pbUpdate
        ret = sebi_region_map_pbUpdate_without_shared_markers
        SebiRegionMapPlayers.refresh_if_needed(self) if defined?(SebiRegionMapPlayers)
        return ret
      end
    end

    if method_defined?(:pbMapScene) && !method_defined?(:sebi_region_map_pbMapScene_without_shared_markers)
      alias sebi_region_map_pbMapScene_without_shared_markers pbMapScene

      def pbMapScene(mode = 0)
        xOffset = 0
        yOffset = 0
        newX = 0
        newY = 0
        @sebi_region_mode = mode
        @sprites["cursor"].x = -SQUAREWIDTH / 2 + (@mapX * SQUAREWIDTH) + (Graphics.width - @sprites["map"].bitmap.width) / 2
        @sprites["cursor"].y = -SQUAREHEIGHT / 2 + (@mapY * SQUAREHEIGHT) + (Graphics.height - @sprites["map"].bitmap.height) / 2
        loop do
          Graphics.update
          Input.update
          pbUpdate
          next if defined?(SebiRegionMapPlayers) && SebiRegionMapPlayers.handle_multiplayer_menu_input(self, mode)
          SebiRegionMapPlayers.handle_marker_input(self, mode) if defined?(SebiRegionMapPlayers)
          if xOffset != 0 || yOffset != 0
            xOffset += xOffset > 0 ? -4 : (xOffset < 0 ? 4 : 0)
            yOffset += yOffset > 0 ? -4 : (yOffset < 0 ? 4 : 0)
            @sprites["cursor"].x = newX - xOffset
            @sprites["cursor"].y = newY - yOffset
            next
          end
          @sprites["mapbottom"].maplocation = pbGetMapLocation(@mapX, @mapY)
          @sprites["mapbottom"].mapdetails = pbGetMapDetails(@mapX, @mapY)
          ox = 0
          oy = 0
          case Input.dir8
          when 1
            oy = 1 if @mapY < BOTTOM
            ox = -1 if @mapX > LEFT
          when 2
            oy = 1 if @mapY < BOTTOM
          when 3
            oy = 1 if @mapY < BOTTOM
            ox = 1 if @mapX < RIGHT
          when 4
            ox = -1 if @mapX > LEFT
          when 6
            ox = 1 if @mapX < RIGHT
          when 7
            oy = -1 if @mapY > TOP
            ox = -1 if @mapX > LEFT
          when 8
            oy = -1 if @mapY > TOP
          when 9
            oy = -1 if @mapY > TOP
            ox = 1 if @mapX < RIGHT
          end
          if ox != 0 || oy != 0
            @mapX += ox
            @mapY += oy
            xOffset = ox * SQUAREWIDTH
            yOffset = oy * SQUAREHEIGHT
            newX = @sprites["cursor"].x + xOffset
            newY = @sprites["cursor"].y + yOffset
          end
          if Input.trigger?(Input::B)
            if @editor && @changed
              if Kernel.pbConfirmMessage(_INTL("Guardar los cambios?")) { pbUpdate }
                pbSaveMapData
              end
              if Kernel.pbConfirmMessage(_INTL("Salir del mapa?")) { pbUpdate }
                break
              end
            else
              break
            end
          elsif Input.trigger?(Input::C) && mode == 1
            healspot = pbGetHealingSpot(@mapX, @mapY)
            if healspot
              if $PokemonGlobal.visitedMaps[healspot[0]] || ($DEBUG && Input.press?(Input::CTRL))
                return healspot
              end
            end
          elsif Input.trigger?(Input::C) && @editor
            pbChangeMapLocation(@mapX, @mapY)
          end
        end
        return nil
      end
    end

    if method_defined?(:pbEndScene) && !method_defined?(:sebi_region_map_pbEndScene_without_shared_markers)
      alias sebi_region_map_pbEndScene_without_shared_markers pbEndScene

      def pbEndScene
        SebiRegionMapPlayers.clear(self) if defined?(SebiRegionMapPlayers)
        return sebi_region_map_pbEndScene_without_shared_markers
      end
    end
  end
end

SebiControls.install_battle_bag_controls_patch if defined?(SebiControls)
SebiControls.install_normal_bag_controls_patch if defined?(SebiControls)

if defined?(NewBattleBag)
  class NewBattleBag
    unless method_defined?(:sebi_controls_update_without_bag_accept_context)
      alias sebi_controls_update_without_bag_accept_context update

      def update
        old_context = defined?(SebiControls) ? SebiControls.battle_bag_input? : false
        SebiControls.battle_bag_input = true if defined?(SebiControls)
        SebiControls.apply_battle_bag_accept(self) if defined?(SebiControls)
        ret = sebi_controls_update_without_bag_accept_context
        SebiControls.apply_battle_bag_accept(self) if defined?(SebiControls)
        return ret
      ensure
        SebiControls.battle_bag_input = old_context if defined?(SebiControls)
      end
    end

    unless method_defined?(:sebi_controls_useItem_without_bag_accept_context?)
      alias sebi_controls_useItem_without_bag_accept_context? useItem?

      def useItem?
        old_context = defined?(SebiControls) ? SebiControls.battle_bag_input? : false
        SebiControls.battle_bag_input = true if defined?(SebiControls)
        SebiControls.prime_battle_bag_accept if defined?(SebiControls)
        return sebi_controls_useItem_without_bag_accept_context?
      ensure
        SebiControls.battle_bag_input = old_context if defined?(SebiControls)
      end
    end
  end
end

if defined?(PokeBattle_Scene)
  class PokeBattle_Scene
    if method_defined?(:pbItemMenu) && !method_defined?(:sebi_controls_pbItemMenu_without_bag_accept_context)
      alias sebi_controls_pbItemMenu_without_bag_accept_context pbItemMenu

      def pbItemMenu(index)
        old_context = defined?(SebiControls) ? SebiControls.battle_bag_input? : false
        SebiControls.install_battle_bag_controls_patch if defined?(SebiControls)
        SebiControls.battle_bag_input = true if defined?(SebiControls)
        SebiControls.prime_battle_bag_accept if defined?(SebiControls)
        return sebi_controls_pbItemMenu_without_bag_accept_context(index)
      ensure
        SebiControls.battle_bag_input = old_context if defined?(SebiControls)
      end
    end
  end
end

class Game_Player
  unless method_defined?(:sebi_mp_passable_without_remotes?)
    alias sebi_mp_passable_without_remotes? passable?

    def passable?(x, y, d)
      ret = sebi_mp_passable_without_remotes?(x, y, d)
      return false if !ret
      collisions_enabled = !defined?(SebiLinkOptions) || SebiLinkOptions.remote_collisions?
      if collisions_enabled && SebiVisualMultiplayer.enabled? && $game_map
        new_x = x + (d == 6 ? 1 : d == 4 ? -1 : 0)
        new_y = y + (d == 2 ? 1 : d == 8 ? -1 : 0)
        return false if SebiVisualMultiplayer.remote_at(new_x, new_y, $game_map.map_id)
      end
      return ret
    end
  end

  unless method_defined?(:sebi_mp_check_event_trigger_there)
    alias sebi_mp_check_event_trigger_there check_event_trigger_there

    def check_event_trigger_there(triggers)
      if SebiVisualMultiplayer.enabled? && (triggers.include?(0) || triggers.include?(2))
        remote = SebiVisualMultiplayer.remote_in_front
        if remote
          SebiVisualMultiplayer.open_player_menu(remote)
          return true
        end
      end
      return sebi_mp_check_event_trigger_there(triggers)
    end
  end
end

module Graphics
  class << self
    unless method_defined?(:sebi_mp_update_without_global_tick)
      alias sebi_mp_update_without_global_tick update

      def update(*args)
        ret = sebi_mp_update_without_global_tick(*args)
        SebiVisualMultiplayer.global_tick if defined?(SebiVisualMultiplayer)
        return ret
      end
    end
  end
end

Events.onMapUpdate += proc { |sender, e|
  SebiVisualMultiplayer.mark_map_update if defined?(SebiVisualMultiplayer)
  SebiVisualMultiplayer.update
  SebiVisualMultiplayer.update_map_player_click if defined?(SebiVisualMultiplayer)
  SebiVisualMultiplayer.update_follow_cancel_input if defined?(SebiVisualMultiplayer)
  SebiVisualMultiplayer.update_follow_player if defined?(SebiVisualMultiplayer)
  SebiVisualMultiplayer.ensure_remote_layer if defined?(SebiVisualMultiplayer)
  SebiControls.install_battle_bag_controls_patch if defined?(SebiControls)
  SebiControls.install_normal_bag_controls_patch if defined?(SebiControls)
  SebiCheats.apply_level_cap_override if defined?(SebiCheats)
  SebiAutoBackups.update if defined?(SebiAutoBackups)
}

Events.onSpritesetCreate += proc { |sender, spriteset, viewport|
  begin
    if SebiVisualMultiplayer.enabled? && spriteset && viewport
      spriteset.addUserSprite(SebiRemotePlayerLayer.new(viewport, spriteset.map))
    end
  rescue Exception
    SebiVisualMultiplayer.log("spriteset hook failed: " + $!.class.to_s + ": " + $!.message.to_s)
  end
}

at_exit do
  SebiVisualMultiplayer.stop_hosted_server(false) if defined?(SebiVisualMultiplayer)
end

# Complete catalogue, initialized even before entering an options menu.
load File.join(File.dirname(__FILE__), "SebiSettingsRegistry.rb")
load File.join(File.dirname(__FILE__), "SebiRandomizer.rb")
SebiSettingsRegistry.initialize_all
load File.join(File.dirname(__FILE__), "SebiUpdater.rb")
