# Player activity, appended locally; never included in the public package.
# RGSS1 has no JSON standard library. Keep IDs independent of the game's RNG.
module SebiActivityLog
  def self.directory
    return SebiLinkPaths.config_path("Historial")
  end

  def self.path
    return File.join(directory, "historial.sebilog")
  end

  def self.timestamp(time = Time.now)
    offset = time.utc_offset
    return time.strftime("%Y-%m-%dT%H:%M:%S") + sprintf("%s%02d:%02d", offset < 0 ? "-" : "+", offset.abs / 3600, offset.abs / 60 % 60)
  end

  def self.safe(default = nil)
    yield
  rescue StandardError
    default
  end

  def self.uid(prefix)
    @sequence = (@sequence || 0) + 1
    now = Time.now
    return "%s-%x-%x-%x-%x" % [prefix, now.to_i, now.usec, Process.pid, @sequence]
  end

  def self.pokemon_id(pokemon)
    id = pokemon.instance_variable_get("@sebilink_activity_id")
    if !id || id.to_s == ""
      id = uid("pkm")
      pokemon.instance_variable_set("@sebilink_activity_id", id)
    end
    return id
  end

  def self.location
    return {
      "map_id" => safe(0) { $game_map.map_id },
      "map_name" => safe("") { pbGetMapNameFromId($game_map.map_id) },
      "x" => safe(nil) { $game_player.x }, "y" => safe(nil) { $game_player.y }
    }
  end

  def self.context(data)
    old = @context
    @context = (old || {}).merge(data)
    begin
      yield
    ensure
      @context = old
    end
  end

  def self.json_string(value)
    text = value.to_s.gsub(/[\\"\x00-\x1f]/) do |char|
      if char == "\\" || char == '"'
        "\\" + char
      else
        "\\u%04x" % char.unpack("C")[0]
      end
    end
    return '"' + text + '"'
  end

  def self.json(value)
    case value
    when NilClass then "null"
    when TrueClass then "true"
    when FalseClass then "false"
    when Numeric then value.to_s
    when Array then "[" + value.map { |v| json(v) }.join(",") + "]"
    when Hash then "{" + value.map { |k, v| json_string(k) + ":" + json(v) }.join(",") + "}"
    else json_string(value)
    end
  end

  # Include custom game attributes too, without executing their getters.
  def self.attributes(value, seen = {})
    case value
    when NilClass, TrueClass, FalseClass, Numeric, String then return value
    when Symbol then return value.to_s
    when Time then return { "unix" => value.to_i, "local" => timestamp(value) }
    end
    return { "reference" => value.class.to_s } if seen[value.object_id]
    seen[value.object_id] = true
    begin
      return value.map { |v| attributes(v, seen) } if value.is_a?(Array)
      if value.is_a?(Hash)
        out = {}
        value.each { |k, v| out[k.to_s] = attributes(v, seen) }
        return out
      end
      out = { "class" => value.class.to_s }
      value.instance_variables.each do |key|
        next if key.to_s == "@sebilink_activity_recovery_depth"
        out[key.to_s] = attributes(value.instance_variable_get(key), seen)
      end
      return out
    ensure
      seen.delete(value.object_id)
    end
  end

  def self.pokemon_data(pokemon)
    return nil if !pokemon
    id = pokemon_id(pokemon)
    data = safe({}) { SebiSaveEditor.pokemon_data(pokemon, "activity", nil) } || {}
    data = data.merge({ "id" => id, "attributes" => attributes(pokemon) })
    data["captured_at"] = pokemon.instance_variable_get("@sebilink_captured_at")
    data["types"] = [safe(nil) { pokemon.type1 }, safe(nil) { pokemon.type2 }].uniq
    return data
  end

  def self.write(event, details = {})
    now = Time.now
    entry = {
      "schema" => 1, "event_id" => uid("event"), "event" => event,
      "date" => now.strftime("%Y-%m-%d"), "time" => now.strftime("%H:%M:%S"),
      "timestamp" => timestamp(now), "unix_time" => now.to_i,
      "trainer" => { "name" => safe("") { $Trainer.name }, "id" => safe(nil) { $Trainer.id } },
      "save_file" => safe(nil) { SebiAutoBackups.current_original_filename },
      "location" => location
    }.merge(details)
    SebiLinkPaths.ensure_config_dir
    return persist_line(json(entry))
  rescue StandardError => error
    @last_error = error.message.to_s
    return false
  end

  def self.setting_text(key, value)
    return "sin configurar" if value == nil
    return "activado" if %w[true yes on si].include?(value.to_s.downcase)
    return "desactivado" if %w[false no off].include?(value.to_s.downcase)
    return value.to_s + "%" if key == "wild_shiny_percent"
    return value.to_s
  end

  def self.settings_changed(before, after, source)
    (before.keys + after.keys).uniq.each do |key|
      value = after[key]
      next if key.to_s =~ /\Aconfig_/ || before[key].to_s == value.to_s && before.has_key?(key) && after.has_key?(key)
      write("setting_changed", { "field" => key.to_s, "old_value" => before[key], "new_value" => value,
        "old_display" => setting_text(key, before[key]), "new_display" => setting_text(key, value),
        "source" => source })
    end
    @observed_settings = after.clone
  end

  def self.poll_native_settings(force = false)
    return if !force && @next_native_poll && Time.now < @next_native_poll
    @next_native_poll = Time.now + 0.5
    if defined?(SebiLinkFileConfig)
      current = SebiLinkFileConfig.read_values(SebiLinkFileConfig::PATH)
      if !@observed_settings
        write("settings_snapshot", { "settings" => current })
      elsif current != @observed_settings
        settings_changed(@observed_settings, current, "file_observation")
      end
      @observed_settings = current.clone
    end
    pending = File.join(directory, "history-pending")
    return if !File.directory?(pending) || Dir.glob(File.join(pending, "*.audit")).empty?
    write("activity_poll", { "source" => "native_setting_context" })
  rescue StandardError => error
    @last_error = error.message.to_s
  end

  def self.health_data(pokemon)
    return { "hp" => safe(nil) { pokemon.hp }, "status" => safe(nil) { pokemon.status },
      "pp" => safe([]) { pokemon.moves.map { |move| move.pp } } }
  end

  def self.healed(pokemon, before, method, force = false)
    return if !owned?(pokemon) || safe(false) { pokemon.isEgg? }
    after = health_data(pokemon)
    return if !force && before == after
    write("pokemon_healed", { "pokemon" => pokemon_data(pokemon), "before" => before, "after" => after,
      "method" => method, "changed" => before != after,
      "source" => (@context || { "kind" => "game" }).merge({ "npc_event_id" => safe(nil) { $game_system.map_interpreter.instance_variable_get("@event_id") } }) })
  end

  def self.party_snapshot
    return safe([]) { $Trainer.party.map { |pokemon| pokemon_data(pokemon) } }
  end

  def self.owned_pokemon
    result = safe([]) { $Trainer.party.compact }.clone
    safe(nil) do
      $PokemonStorage.boxes.each do |box|
        (0...box.length).each { |slot| result.push(box[slot]) if box[slot] }
      end
    end
    return result.uniq
  end

  def self.owned_snapshot
    result = {}
    owned_pokemon.each { |pokemon| result[pokemon_id(pokemon)] = pokemon_data(pokemon) }
    return result
  end

  def self.action_arguments(value)
    return value.map { |entry| action_arguments(entry) } if value.is_a?(Array)
    if value.is_a?(Hash)
      result = {}
      value.each { |key, entry| result[key.to_s] = action_arguments(entry) }
      return result
    end
    return pokemon_data(value) if value.is_a?(PokeBattle_Pokemon)
    return attributes(value) if value == nil || value == true || value == false || value.is_a?(Numeric) || value.is_a?(String) || value.is_a?(Symbol)
    return { "class" => value.class.to_s, "name" => safe(nil) { value.name },
      "remote_id" => safe(nil) { value.remote_id }, "map_id" => safe(nil) { value.remote_map_id } }
  end

  def self.action_fields(args)
    command = args[0].is_a?(Hash) ? args[0] : {}
    fields = command["args"].is_a?(Hash) ? command["args"] : {}
    id = fields["id"].to_i
    trainer = safe(nil) { attributes($Trainer) }
    trainer.delete("@party") if trainer.is_a?(Hash)
    result = { "trainer" => trainer, "nuzlocke" => safe(nil) { $PokemonGlobal.nuzlocke } }
    result["switch"] = safe(nil) { $game_switches[id] } if command["cmd"] == "switch_set"
    result["variable"] = safe(nil) { attributes($game_variables[id]) } if command["cmd"] == "variable_set"
    return result
  end

  def self.action(name, args)
    before = party_snapshot
    owned_before = safe({}) { owned_snapshot }
    bag_before = safe(nil) { attributes($PokemonBag) }
    fields_before = action_fields(args)
    money = safe(nil) { $Trainer.money }
    event_location = location
    result = nil
    write("sebilink_action_started", { "action" => name, "arguments" => action_arguments(args),
      "before_party" => before, "location" => event_location })
    begin
      result = context({ "kind" => "sebilink_action", "action" => name }) { yield }
      owned_after = safe({}) { owned_snapshot }
      changes = []
      (owned_before.keys + owned_after.keys).uniq.each do |id|
        changes.push({ "id" => id, "before" => owned_before[id], "after" => owned_after[id] }) if owned_before[id] != owned_after[id]
      end
      write("sebilink_action", { "action" => name, "arguments" => action_arguments(args),
        "before_party" => before, "after_party" => party_snapshot,
        "pokemon_changes" => changes, "inventory_before" => bag_before, "inventory_after" => safe(nil) { attributes($PokemonBag) },
        "fields_before" => fields_before, "fields_after" => action_fields(args),
        "money_before" => money, "money_after" => safe(nil) { $Trainer.money },
        "result" => attributes(result), "location" => event_location })
      return result
    rescue StandardError => error
      write("sebilink_action_failed", { "action" => name, "arguments" => action_arguments(args),
        "before_party" => before, "after_party" => party_snapshot, "error" => error.message.to_s,
        "location" => event_location })
      raise
    end
  end

  def self.trade(index, source, partner)
    original = safe(nil) { $Trainer.party[index] }
    sent = safe(nil) { pokemon_data(original) }
    result = yield
    received = safe(nil) { $Trainer.party[index] }
    if original && received && !original.equal?(received)
      write("pokemon_traded", { "sent" => sent, "received" => safe(nil) { pokemon_data(received) },
        "source" => source, "partner" => partner, "party_index" => index })
    end
    return result
  end

  def self.use_item(method, args)
    target = args[1]
    pokemon = target.respond_to?(:pokemon) ? target.pokemon : target
    return yield if !pokemon.is_a?(PokeBattle_Pokemon) || !owned?(pokemon)
    before = health_data(pokemon)
    snapshot = pokemon_data(pokemon)
    depth = pokemon.instance_variable_get("@sebilink_activity_recovery_depth").to_i
    pokemon.instance_variable_set("@sebilink_activity_recovery_depth", depth + 1)
    begin
      return context({ "kind" => "item", "item" => item_data(args[0], 1) }) do
        result = yield
        healed(pokemon, before, method) if depth == 0
        write("item_used", { "item" => item_data(args[0], 1), "before" => snapshot,
          "after" => pokemon_data(pokemon), "method" => method }) if result
        result
      end
    ensure
      pokemon.instance_variable_set("@sebilink_activity_recovery_depth", depth)
    end
  end

  def self.crypto_script
    return File.join(File.dirname(__FILE__), "SebiActivityCrypto.ps1")
  end

  def self.launch_crypto(mode)
    args = "-Mode " + mode + " -ConfigDir " + SebiSaveManager.quote_arg(SebiLinkPaths.config_dir)
    if mode == "Writer"
      @pipe_name = "SebiLink-PokemonZ-History-" + Win32API.new("kernel32", "GetCurrentProcessId", "", "l").call.to_s
      args += " -PipeName " + @pipe_name + " -ParentId " + @pipe_name.split("-").last
    end
    return SebiSaveManager.open_powershell_script(crypto_script, args)
  end

  def self.persist_line(line)
    # Plain events stay only in RAM and the private Windows pipe, never on disk.
    line = line.dup
    line.force_encoding("BINARY") if line.respond_to?(:force_encoding)
    @pending ||= []
    @pending.push(line)
    flush_pending
    return @pending.empty?
  end

  def self.flush_pending
    return if !@pending || @pending.empty? || @flushing
    @flushing = true
    begin
      if !@worker_launched
        @worker_launched = launch_crypto("Writer")
        raise "No se pudo iniciar el cifrado del historial." if !@worker_launched
      end
      if !@pipe_handle
        handle = Win32API.new("kernel32", "CreateFileA", "pllllll", "l").call(
          "\\\\.\\pipe\\" + @pipe_name, 0xC0000000, 0, 0, 3, 0, 0)
        if handle == -1 || handle == 0
          @last_error = "Historial pendiente de cifrar. Comprueba la configuracion o Historial/historial-error.txt."
          return
        end
        @pipe_handle = handle
      end
      while !@pending.empty?
        line = @pending[0]
        bytes = [line.length].pack("V") + line
        offset = 0
        while offset < bytes.length
          count = [0].pack("V")
          ok = Win32API.new("kernel32", "WriteFile", "lplpl", "l").call(@pipe_handle, bytes[offset..-1], bytes.length - offset, count, 0)
          written = count.unpack("V")[0]
          raise "No se pudo enviar el registro para cifrar." if ok == 0 || written == 0
          offset += written
        end
        reply = "\0"
        count = [0].pack("V")
        ok = Win32API.new("kernel32", "ReadFile", "lplpl", "l").call(@pipe_handle, reply, 1, count, 0)
        raise "El historial cifrado no pudo verificarse o guardarse." if ok == 0 || count.unpack("V")[0] != 1 || reply.unpack("C")[0] != 1
        @pending.shift
      end
      @last_error = nil
    rescue StandardError => error
      @last_error = error.message.to_s
      close_pipe
    ensure
      @flushing = false
    end
  end

  def self.close_pipe
    Win32API.new("kernel32", "CloseHandle", "l", "l").call(@pipe_handle) if @pipe_handle
    @pipe_handle = nil
  rescue StandardError
    @pipe_handle = nil
  end

  def self.owned?(pokemon)
    return true if safe(false) { $Trainer.party.include?(pokemon) }
    return safe(false) do
      $PokemonStorage.boxes.any? { |box| (0...box.length).any? { |slot| box[slot].equal?(pokemon) } }
    end
  end

  def self.begin_battle(battle)
    return if battle.instance_variable_get("@sebilink_activity_battle")
    state = { "id" => uid("battle"), "location" => location, "wild" => [], "outcomes" => {} }
    battle.instance_variable_set("@sebilink_activity_battle", state)
    if !safe(nil) { battle.opponent }
      party = safe([]) { battle.party2 } || []
      party.each do |pokemon|
        next if !pokemon
        state["wild"].push(pokemon)
        write("wild_encounter", { "battle_id" => state["id"], "pokemon" => pokemon_data(pokemon), "location" => state["location"] })
      end
    end
  end

  def self.with_battle(battle)
    old = @battle
    @battle = battle
    begin
      yield
    ensure
      @battle = old
    end
  end

  def self.capture(battle, pokemon)
    state = battle.instance_variable_get("@sebilink_activity_battle")
    return if !state
    id = pokemon_id(pokemon)
    return if state["outcomes"][id] == "captured"
    stored = owned?(pokemon)
    stored ||= safe(false) { pbBugContestState.lastPokemon.equal?(pokemon) } if battle.is_a?(PokeBattle_BugContestBattle)
    state["outcomes"][id] = "captured"
    pokemon.instance_variable_set("@sebilink_captured_at", timestamp)
    write("pokemon_captured", { "battle_id" => state["id"], "pokemon" => pokemon_data(pokemon), "retained" => stored ? true : false, "location" => state["location"] })
  end

  def self.faint(battler)
    battle = battler.instance_variable_get("@battle")
    pokemon = battler.pokemon
    return if !pokemon || !battle
    state = battle.instance_variable_get("@sebilink_activity_battle")
    details = { "pokemon" => pokemon_data(pokemon), "battle_id" => state ? state["id"] : nil }
    details["location"] = state["location"] if state
    if safe(false) { battle.pbOwnedByPlayer?(battler.index) }
      permanent = safe(false) { $PokemonGlobal.nuzlocke && battle.internalbattle }
      details["permanent"] = permanent ? true : false
      details["cause"] = "battle"
      write(permanent ? "pokemon_death" : "pokemon_fainted", details)
    elsif state && state["wild"].include?(pokemon)
      state["outcomes"][pokemon_id(pokemon)] = "defeated"
      write("wild_defeated", details)
    end
  end

  def self.outside_faint(pokemon)
    return if @battle || !safe(false) { $Trainer.party.include?(pokemon) }
    return if safe(false) { pokemon.isEgg? }
    permanent = safe(false) { $PokemonGlobal.nuzlocke }
    write(permanent ? "pokemon_death" : "pokemon_fainted", {
      "pokemon" => pokemon_data(pokemon), "permanent" => permanent ? true : false,
      "cause" => "outside_battle"
    })
  end

  def self.end_battle(battle, decision)
    state = battle.instance_variable_get("@sebilink_activity_battle")
    return if !state
    state["wild"].each do |pokemon|
      id = pokemon_id(pokemon)
      outcome = state["outcomes"][id]
      outcome ||= "defeated" if safe(1) { pokemon.hp }.to_i <= 0
      outcome ||= (decision.to_i == 3 ? "escaped" : "not_captured")
      write("wild_result", {
        "battle_id" => state["id"], "pokemon" => pokemon_data(pokemon),
        "outcome" => outcome, "decision" => decision, "location" => state["location"]
      })
    end
    battle.instance_variable_set("@sebilink_activity_battle", nil)
  end

  def self.item_data(item, quantity)
    id = item.is_a?(Integer) ? item : getID(PBItems, item)
    return { "id" => id, "name" => safe(id.to_s) { PBItems.getName(id) }, "quantity" => quantity }
  end

  def self.item_received(item, quantity)
    return if quantity <= 0 || (@context && @context["kind"] == "shop_insert")
    write("item_obtained", { "item" => item_data(item, quantity), "source" => @context || { "kind" => "game" } })
  end

  def self.shop_pending(adapter, item, quantity)
    pending = adapter.instance_variable_get("@sebilink_activity_items") || {}
    pending[item] = (pending[item] || 0) + quantity
    adapter.instance_variable_set("@sebilink_activity_items", pending)
  end

  def self.shop_commit(adapter, cost = nil)
    pending = adapter.instance_variable_get("@sebilink_activity_items") || {}
    pending.each do |item, quantity|
      next if quantity <= 0
      data = { "item" => item_data(item, quantity), "source" => @context || { "kind" => "shop", "via" => "game" } }
      data["total_price"] = cost if cost
      data["unit_price"] = cost.to_f / quantity if cost
      write(cost ? "item_purchased" : "item_obtained", data)
    end
    adapter.instance_variable_set("@sebilink_activity_items", {})
  end

  def self.open_file
    SebiLinkPaths.ensure_config_dir
    poll_native_settings(true)
    flush_pending
    if @last_error
      Kernel.pbMessage(_INTL("No se pudo escribir un registro: {1}", @last_error))
    end
    Kernel.pbMessage(_INTL("No se pudo abrir el historial cifrado.")) if !launch_crypto("View")
  rescue StandardError
    Kernel.pbMessage(_INTL("Historial: {1}", path))
  end
end

# Every selection in a SebiLink submenu is dated, including cancelled choices.
module Kernel
  class << self
    if method_defined?(:pbMessage) && !method_defined?(:sebi_activity_message)
      alias sebi_activity_message pbMessage
      def pbMessage(*args, &block)
        result = sebi_activity_message(*args, &block)
        context = SebiActivityLog.instance_variable_get("@context")
        if context && (context["menu"] || context["action"]) && args[1].is_a?(Array)
          choice = result.is_a?(Integer) && result >= 0 && result < args[1].length ? args[1][result] : nil
          SebiActivityLog.write("sebilink_option_selected", { "menu" => args[0].to_s,
            "selected_index" => result, "selected_option" => choice, "source" => context })
        end
        return result
      end
    end
  end
end

Object.constants.each do |constant|
  module_name = constant.to_s
  next if module_name !~ /\ASebi/ || module_name == "SebiActivityLog"
  target = Object.const_get(constant)
  next if !target.is_a?(Module)
  singleton = class << target; self; end
  target.singleton_methods.each do |method|
    name = method.to_s
    next if name !~ /\A(?:open_menu|open_main_menu|open_manager|open_.*_menu)\z/
    original = "sebi_activity_menu_" + name
    next if singleton.method_defined?(original)
    singleton.send(:alias_method, original, method)
    singleton.class_eval("def #{name}(*args)\n SebiActivityLog.context({'menu'=>'#{module_name}.#{name}'}) { #{original}(*args) }\n end")
  end
end

if defined?(ItemHandlers)
  singleton = class << ItemHandlers; self; end
  [:triggerUseOnPokemon, :triggerBattleUseOnPokemon, :triggerBattleUseOnBattler].each do |name|
    next if !ItemHandlers.respond_to?(name)
    original = "sebi_activity_item_" + name.to_s
    next if singleton.method_defined?(original)
    singleton.send(:alias_method, original, name)
    singleton.class_eval("def #{name}(*args)\n SebiActivityLog.use_item('#{name}', args) { #{original}(*args) }\n end")
  end
end

if defined?(Input)
  module Input
    class << self
      unless method_defined?(:sebi_activity_update)
        alias sebi_activity_update update
        def update
          result = sebi_activity_update
          SebiActivityLog.poll_native_settings
          SebiActivityLog.flush_pending
          return result
        end
      end
    end
  end
end
at_exit { SebiActivityLog.close_pipe }

# A failed snapshot or unavailable disk must not interrupt gameplay.
class << SebiActivityLog
  [:begin_battle, :capture, :faint, :outside_faint, :end_battle,
   :item_received, :shop_pending, :shop_commit, :settings_changed, :healed].each do |name|
    original = "unguarded_" + name.to_s
    next if method_defined?(original)
    alias_method original, name
    # Explicit method body also works on RGSS Ruby 1.8 (no loop closures).
    class_eval("def #{name}(*args)\n #{original}(*args)\n rescue StandardError => error\n @last_error = error.message.to_s\n nil\n end")
  end
end

# Install after all original/randomizer hooks so snapshots reflect the real result.
[PokeBattle_Battle, PokeBattle_SafariZone].each do |klass|
  klass.class_eval do
    unless method_defined?(:sebi_activity_start_battle)
      alias sebi_activity_start_battle pbStartBattle
      def pbStartBattle(*args)
        SebiActivityLog.begin_battle(self)
        result = nil
        begin
          result = SebiActivityLog.with_battle(self) { sebi_activity_start_battle(*args) }
          return result
        ensure
          SebiActivityLog.end_battle(self, result || @decision || 0)
        end
      end
    end
  end
end

[PokeBattle_BattleCommon, PokeBattle_BugContestBattle].each do |klass|
  klass.class_eval do
    unless instance_methods(false).map { |m| m.to_s }.include?("sebi_activity_store_pokemon")
      alias sebi_activity_store_pokemon pbStorePokemon
      def pbStorePokemon(pokemon)
        result = sebi_activity_store_pokemon(pokemon)
        SebiActivityLog.capture(self, pokemon)
        return result
      end
    end
  end
end

class PokeBattle_Battler
  unless method_defined?(:sebi_activity_faint)
    alias sebi_activity_faint pbFaint
    def pbFaint(*args)
      before = @fainted
      result = sebi_activity_faint(*args)
      SebiActivityLog.faint(self) if !before && @fainted
      return result
    end
  end
end

class PokeBattle_Pokemon
  unless method_defined?(:sebi_activity_hp)
    alias sebi_activity_hp hp=
    def hp=(value)
      before = @hp
      result = self.sebi_activity_hp(value)
      SebiActivityLog.outside_faint(self) if before && before > 0 && @hp <= 0
      return result
    end
  end
end

module Kernel
  class << self
    unless method_defined?(:sebi_activity_item_ball)
      alias sebi_activity_item_ball pbItemBall
      alias sebi_activity_receive_item pbReceiveItem
      def pbItemBall(*args)
        return SebiActivityLog.context({ "kind" => "ground" }) { sebi_activity_item_ball(*args) }
      end
      def pbReceiveItem(*args)
        return SebiActivityLog.context({ "kind" => "gift" }) { sebi_activity_receive_item(*args) }
      end
    end
  end
end

class PokemonBag
  unless method_defined?(:sebi_activity_store_item)
    alias sebi_activity_store_item pbStoreItem
    def pbStoreItem(item, quantity = 1)
      before = pbQuantity(item)
      result = sebi_activity_store_item(item, quantity)
      SebiActivityLog.item_received(item, pbQuantity(item) - before)
      return result
    end
  end
end

class PokemonMartAdapter
  unless method_defined?(:sebi_activity_add_item)
    alias sebi_activity_add_item addItem
    alias sebi_activity_remove_item removeItem
    alias sebi_activity_set_money setMoney
    def addItem(item)
      before = getQuantity(item)
      result = SebiActivityLog.context({ "kind" => "shop_insert" }) { sebi_activity_add_item(item) }
      SebiActivityLog.shop_pending(self, item, getQuantity(item) - before)
      return result
    end
    def removeItem(item)
      before = getQuantity(item)
      result = sebi_activity_remove_item(item)
      SebiActivityLog.shop_pending(self, item, getQuantity(item) - before)
      return result
    end
    def setMoney(value)
      before = getMoney
      result = sebi_activity_set_money(value)
      SebiActivityLog.shop_commit(self, before - getMoney) if getMoney <= before
      return result
    end
  end
end

class PokemonMartScreen
  unless method_defined?(:sebi_activity_buy_screen)
    alias sebi_activity_buy_screen pbBuyScreen
    alias sebi_activity_mart_display pbDisplayPaused
    def pbBuyScreen(*args)
      @adapter.instance_variable_set("@sebilink_activity_items", {})
      return SebiActivityLog.context({ "kind" => "shop" }) { sebi_activity_buy_screen(*args) }
    ensure
      SebiActivityLog.shop_commit(@adapter)
    end
    def pbDisplayPaused(*args)
      SebiActivityLog.shop_commit(@adapter)
      return sebi_activity_mart_display(*args)
    end
  end
end

class Object
  unless method_defined?(:sebi_activity_mart) || private_method_defined?(:sebi_activity_mart)
    alias sebi_activity_mart pbPokemonMart
    def pbPokemonMart(*args)
      return SebiActivityLog.context({ "via" => "game" }.merge(SebiActivityLog.instance_variable_get("@context") || {})) { sebi_activity_mart(*args) }
    end
  end
end

# Full/partial recovery, including the original game's centres and item effects.
class PokeBattle_Pokemon
  [:heal, :healHP, :healStatus, :healPP, :hp=, :status=].each do |name|
    next if !method_defined?(name)
    original = "sebi_activity_recovery_" + name.to_s.sub("=", "_set")
    next if method_defined?(original)
    alias_method original, name
    class_eval("def #{name}(*args)\n" +
      " before = SebiActivityLog.health_data(self)\n" +
      " depth = @sebilink_activity_recovery_depth.to_i\n" +
      " @sebilink_activity_recovery_depth = depth + 1\n" +
      " begin\n result = #{original}(*args)\n ensure\n @sebilink_activity_recovery_depth = depth\n end\n" +
      " after = SebiActivityLog.health_data(self)\n" +
      " recovered = after['hp'].to_i > before['hp'].to_i || (before['status'].to_i != 0 && after['status'].to_i == 0)\n" +
      " after['pp'].each_with_index { |pp, i| recovered = true if pp.to_i > before['pp'][i].to_i }\n" +
      " SebiActivityLog.healed(self, before, '#{name}', #{name == :heal}) if depth == 0 && (recovered || #{name == :heal})\n" +
      " return result\n end")
  end
end

class Object
  if (method_defined?(:pbHealAll) || private_method_defined?(:pbHealAll)) && !method_defined?(:sebi_activity_heal_all) && !private_method_defined?(:sebi_activity_heal_all)
    alias sebi_activity_heal_all pbHealAll
    def pbHealAll(*args)
      return SebiActivityLog.context({ "recovery" => "party_heal" }) { sebi_activity_heal_all(*args) }
    end
  end
  if (method_defined?(:pbStartTrade) || private_method_defined?(:pbStartTrade)) && !method_defined?(:sebi_activity_trade) && !private_method_defined?(:sebi_activity_trade)
    alias sebi_activity_trade pbStartTrade
    def pbStartTrade(index, newpoke, nickname, partner, *args)
      source = SebiActivityLog.instance_variable_get("@context") || { "kind" => "game_trade" }
      return SebiActivityLog.trade(index, source, partner) { sebi_activity_trade(index, newpoke, nickname, partner, *args) }
    end
  end
end

# Keep action arguments/results and real Pokemon states, including hotkeys/F12.
# Use explicit generated bodies for RGSS1 rather than closures over loop variables.
{
  "SebiLinkHub" => [:run_action],
  "SebiSaveEditor" => [:apply_command_live],
  "SebiSaveManager" => [:run_command, :restore_path],
  "SebiPokemonCenter" => [:heal_party, :execute_shop, :execute_trade, :open_move_reminder, :open_ability_menu, :change_ability_fallback, :open_form_menu],
  "SebiSpecialActions" => [:wonder_trade_daily, :random_egg_trade_daily, :start_training_battle],
  "SebiCheats" => [:transfer_shiny, :give_sacred_ashes_quantity, :equalize_party_levels, :equalize_storage_levels, :equalize_current_box_levels],
  "SebiVisualMultiplayer" => [:teleport_to_player, :try_complete_trade],
  "SebiSavedTeams" => [:save_current_party]
}.each do |module_name, methods|
  next if !Object.const_defined?(module_name.to_sym)
  target = Object.const_get(module_name.to_sym)
  singleton = class << target; self; end
  methods.each do |name|
    next if !target.respond_to?(name)
    original = "sebi_activity_action_" + name.to_s
    next if singleton.method_defined?(original)
    singleton.send(:alias_method, original, name)
    singleton.class_eval("def #{name}(*args)\n SebiActivityLog.action('#{module_name}.#{name}', args) { #{original}(*args) }\n end")
  end
end
