# SebiLink randomizer for Pokemon Z. Player preferences live in sebilink.ini.
module SebiRandomizer
  REGIONS = ["Kanto (Gen. 1)", "Johto (Gen. 2)", "Hoenn (Gen. 3)",
    "Sinnoh (Gen. 4)", "Teselia (Gen. 5)", "Kalos (Gen. 6)",
    "Alola (Gen. 7)", "Galar / Hisui (Gen. 8)", "Paldea (Gen. 9)"]
  GROUPS = [
    ["Pokemon", [
      ["wild", "Salvajes y rutas", "Sorteo independiente en CADA encuentro, incluida pesca."],
      ["trainer", "Entrenadores", "Especies nuevas cada vez que cargas un equipo rival."],
      ["gym", "Lideres de gimnasio", "Regentes y revanchas; independiente de entrenadores."],
      ["starter", "Iniciales", "Opciones aleatorias estables hasta elegir el inicial."],
      ["fossil", "Fosiles", "Especie nueva cada vez que revives un fosil."],
      ["npc_trade", "Intercambios de NPC", "Randomiza el Pokemon recibido; conserva la peticion."],
      ["gift", "Pokemon de regalo", "Incluye huevos regalados; conserva Pokemon ya existentes."]]],
    ["Habilidades y movimientos", [
      ["abilities", "Habilidades", "Habilidad aleatoria por individuo generado."],
      ["level_moves", "Movimientos por nivel", "Movepool por individuo; se conserva al guardar."],
      ["egg_moves", "Movimientos por huevo", "Cambia los ataques heredables, conservando la herencia."],
      ["tm_moves", "Movimientos de MT", "Cada MT tiene un ataque estable por partida; conserva MO."],
      ["tutor_moves", "Movimientos de tutor", "Ataque nuevo al abrir un tutor; permite aprenderlo."]]],
    ["Objetos y tiendas", [
      ["shop_items", "Objetos de tiendas", "Nuevo catalogo al abrir; conserva objetos de historia."],
      ["shop_prices", "Precios de tiendas", "Precios estables durante esa visita."],
      ["ground_items", "Objetos del suelo", "Nuevo objeto por recogida; conserva objetos importantes."],
      ["reward_items", "Regalos y recompensas", "Randomiza objetos recibidos; conserva los de historia."],
      ["trainer_items", "Objetos de entrenadores", "Randomiza objetos equipados del rival."],
      ["wild_items", "Objetos de salvajes", "Randomiza objetos equipados de Pokemon salvajes."]]],
    ["Legendarios y miticos", [
      ["wild_legendary", "Legendarios salvajes", "Permite legendarios en los encuentros aleatorios."],
      ["wild_mythical", "Miticos salvajes", "Permite singulares en los encuentros aleatorios."],
      ["trainer_legendary", "Legendarios entrenadores", "Permite legendarios en entrenadores y regentes."],
      ["trainer_mythical", "Miticos entrenadores", "Permite singulares en entrenadores y regentes."],
      ["gift_legendary", "Legendarios regalos", "Permite legendarios en iniciales, fosiles y regalos."],
      ["gift_mythical", "Miticos regalos", "Permite singulares en iniciales, fosiles y regalos."],
      ["donation_legendary", "Legendarios donaciones", "Filtra Intercambio prodigio y huevo aleatorio."],
      ["donation_mythical", "Miticos donaciones", "Filtra Intercambio prodigio y huevo aleatorio."]]],
    ["Progresion y precios", [
      ["progression", "Progresion por nivel", "OFF: cualquier evolucion desde el comienzo."],
      ["first_evolution", "Primera evolucion", "Nivel maximo del equipo para permitir etapa 1.", 1, 100],
      ["second_evolution", "Segunda evolucion", "Nivel maximo del equipo para permitir etapa 2.", 1, 100],
      ["price_min", "Precio minimo", "Minimo para precios aleatorios de compra.", 1, 99999],
      ["price_max", "Precio maximo", "Maximo para precios aleatorios de compra.", 1, 99999]]],
    ["Formas regionales y Pokemon de Z", [
      ["regional_forms", "Formas regionales", "Permite formas oficiales de Alola, Galar, Hisui y Paldea."],
      ["custom_species", "Pokemon propios de Z", "Permite especies y evoluciones inventadas en Pokemon Z."],
      ["custom_forms", "Formas propias de Z", "Permite variantes de Z, como Dugtrio de agua."]]]
  ]

  def self.defaults
    ret = {"enabled" => false, "regions" => [1,2,3,4,5,6,7,8,9],
      "first_evolution" => 16, "second_evolution" => 36,
      "price_min" => 100, "price_max" => 10000, "tm_map" => {}, "egg_map" => {},
      "starters" => [], "revision" => 0}
    GROUPS.each { |g| g[1].each { |row| ret[row[0]] = false if row.length == 3 } }
    %w[wild trainer gym starter fossil npc_trade gift wild_legendary wild_mythical
      trainer_legendary trainer_mythical gift_legendary gift_mythical
      donation_legendary donation_mythical].each { |key| ret[key] = true }
    return ret
  end

  def self.state
    return nil if !$PokemonGlobal
    saved = $PokemonGlobal.instance_variable_get("@sebi_randomizer")
    return saved if !defined?(SebiLinkFileConfig) # Standalone offline compatibility.
    return @settings if @settings_global.equal?($PokemonGlobal)
    return nil if !saved && !SebiLinkFileConfig.has_key?("randomizer_enabled")
    settings = defaults
    missing = {}
    option_keys.each do |key|
      ini_key = "randomizer_" + key
      if key == "enabled" && !saved && SebiLinkFileConfig.needs_migration?(ini_key) && $game_switches && defined?(RandomizedChallenge) && $game_switches[RandomizedChallenge::SWITCH]
        settings[key] = true
        missing[ini_key] = true
      elsif SebiLinkFileConfig.has_key?(ini_key) && !(saved.is_a?(Hash) && saved.has_key?(key) && SebiLinkFileConfig.needs_migration?(ini_key))
        original = settings[key]
        settings[key] = if key == "regions"
          SebiLinkFileConfig.get(ini_key, "").split(",").map { |v| v.to_i }.select { |v| v >= 1 && v <= 9 }.uniq.sort
        elsif original == true || original == false
          SebiLinkFileConfig.get_bool(ini_key, original)
        else
          SebiLinkFileConfig.get_int(ini_key, original)
        end
      else
        settings[key] = saved[key] if saved.is_a?(Hash) && saved.has_key?(key)
        missing[ini_key] = key == "regions" ? settings[key].join(",") : settings[key]
      end
    end
    settings["regions"] = [1,2,3,4,5,6,7,8,9] if settings["regions"].empty?
    %w[first_evolution second_evolution].each { |k| settings[k] = [[settings[k].to_i, 1].max, 100].min }
    %w[price_min price_max].each { |k| settings[k] = [[settings[k].to_i, 1].max, 99999].min }
    settings["second_evolution"] = [settings["first_evolution"], settings["second_evolution"]].max
    settings["price_max"] = [settings["price_min"], settings["price_max"]].max
    SebiLinkFileConfig.set_many(missing) if !missing.empty?
    # These are generated game results, never player preferences.
    runtime = saved.is_a?(Hash) ? saved : {}
    runtime["tm_map"] = {} if !runtime["tm_map"].is_a?(Hash)
    runtime["egg_map"] = {} if !runtime["egg_map"].is_a?(Hash)
    runtime["starters"] = [] if !runtime["starters"].is_a?(Array)
    option_keys.each { |key| runtime.delete(key) }
    $PokemonGlobal.instance_variable_set("@sebi_randomizer", runtime)
    %w[tm_map egg_map starters].each { |key| settings[key] = runtime[key] }
    @settings_global = $PokemonGlobal
    @settings = settings
    @pools = {}
    if $game_switches && defined?(RandomizedChallenge)
      $game_switches[RandomizedChallenge::SWITCH] = settings["enabled"] && settings["starter"]
    end
    return settings
  end

  def self.option_keys
    @option_keys ||= defaults.keys - %w[tm_map egg_map starters revision]
    return @option_keys
  end

  def self.persist_preferences
    return if !defined?(SebiLinkFileConfig)
    changes = {}
    option_keys.each do |key|
      changes["randomizer_" + key] = key == "regions" ? state[key].join(",") : state[key]
    end
    SebiLinkFileConfig.set_many(changes)
  end

  def self.manage
    return nil if !$PokemonGlobal
    if !state
      settings = defaults
      settings["enabled"] = true if $game_switches && defined?(RandomizedChallenge) && $game_switches[RandomizedChallenge::SWITCH]
      $PokemonGlobal.instance_variable_set("@sebi_randomizer", settings)
    end
    return state
  end

  def self.active?(key = nil)
    s = state
    return false if !s || !s["enabled"] || @suspended.to_i > 0
    return !key || s[key] == true
  end

  def self.suspend
    @suspended = @suspended.to_i + 1
    begin
      return yield
    ensure
      @suspended -= 1
    end
  end

  def self.context(domain)
    old = @domain
    @domain = domain
    begin
      return yield
    ensure
      @domain = old
    end
  end

  def self.domain
    return @domain
  end

  def self.id(mod, value)
    return value.to_i if value.is_a?(Numeric)
    return getID(mod, value)
  end

  def self.catalog
    return @catalog if @catalog
    rows = []
    path = File.join(File.dirname(__FILE__), "randomizer-species.txt")
    File.open(path, "rb") do |file|
      file.each_line do |line|
        next if line[0,1] == "#" || line.strip == ""
        parts = line.strip.split("|", -1)
        species = parts[0].to_i
        # A stale/generated catalog must never silently assign a different species.
        next if id(PBSpecies, parts[1].to_sym) != species
        forms = (parts[5] || "").split(",").map do |v|
          f = v.split(":")
          [f[0].to_i, f[1].to_i, f[2]]
        end
        rows.push([species, parts[2].to_i, parts[3], parts[4].to_i, forms])
      end
    end
    raise "Catalogo SebiLink vacio o incompatible" if rows.empty?
    @catalog = rows
    return rows
  end

  def self.highest_level
    return 5 if !$Trainer || !$Trainer.party
    levels = $Trainer.party.select { |p| p && !p.isEgg? }.map { |p| p.level.to_i }
    return levels.empty? ? 5 : levels.max
  end

  def self.legend_group(domain)
    return "wild" if domain == "wild"
    return "trainer" if domain == "trainer" || domain == "gym"
    return "donation" if domain == "donation"
    return "gift"
  end

  def self.allowed?(row, domain, progression = true)
    s = state
    return false if !s || !s["regions"].include?(row[1])
    return false if row[2] == "c" && !s["custom_species"]
    group = legend_group(domain)
    return false if row[2] == "l" && !s[group + "_legendary"]
    return false if row[2] == "m" && !s[group + "_mythical"]
    if progression && s["progression"]
      level = highest_level
      return false if row[3] >= 1 && level < s["first_evolution"]
      return false if row[3] >= 2 && level < s["second_evolution"]
    end
    return true
  end

  def self.pool(domain)
    key = [state.object_id, state["revision"], domain, state["progression"] ? highest_level : 0]
    @pools ||= {}
    @pools.clear if @pools.length > 80
    @pools[key] ||= catalog.select { |row| allowed?(row, domain) }
    return @pools[key]
  end

  def self.choose(domain)
    rows = pool(domain)
    raise "No hay Pokemon permitidos. Revisa Region y los filtros del randomizador." if rows.empty?
    # No mapping original->replacement, route table or encounter seed/cache.
    return rows[rand(rows.length)]
  end

  def self.form_for(row)
    s = state
    forms = [0]
    row[4].each do |f|
      next if !s["regions"].include?(f[1])
      next if f[2] == "r" && !s["regional_forms"]
      next if f[2] == "c" && !s["custom_forms"]
      forms.push(f[0])
    end
    return forms[rand(forms.length)]
  end

  def self.valid_settings?
    s = state
    return false if !s || s["regions"].empty?
    return false if s["price_min"] > s["price_max"]
    return false if s["first_evolution"] > s["second_evolution"]
    domains = %w[wild trainer gym starter fossil npc_trade gift]
    return domains.all? { |d| !s[d] || !pool(d).empty? }
  end

  def self.change(key, value)
    s = manage
    old = s[key]
    s[key] = value
    s["revision"] += 1
    @pools = {}
    if !valid_settings?
      s[key] = old
      s["revision"] += 1
      @pools = {}
      Kernel.pbMessage(_INTL("Ese ajuste deja un filtro sin Pokemon o un rango invalido. Se mantiene el anterior."))
      return false
    end
    begin
      persist_preferences
    rescue StandardError => error
      s[key] = old
      s["revision"] += 1
      @pools = {}
      Kernel.pbMessage(_INTL("No se pudo guardar el ajuste en sebilink.ini: {1}", error.message))
      return false
    end
    apply_tm_moves
    generate_starters if %w[regions regional_forms custom_species custom_forms progression first_evolution second_evolution starter gift_legendary gift_mythical].include?(key)
    if $game_switches && defined?(RandomizedChallenge)
      $game_switches[RandomizedChallenge::SWITCH] = s["enabled"] && s["starter"]
    end
    return true
  end

  def self.status(value)
    return value == true ? "ON" : value == false ? "OFF" : value.to_s
  end

  def self.open_group(group)
    loop do
      commands = group[1].map { |r| _INTL("{1}: {2}", r[1], status(state[r[0]])) }
      commands.push(_INTL("Volver"))
      selected = Kernel.pbMessage(_INTL(group[0]), commands, commands.length)
      break if selected < 0 || selected >= group[1].length
      row = group[1][selected]
      if row.length == 3
        change(row[0], !state[row[0]])
      else
        params = ChooseNumberParams.new
        params.setRange(row[3], row[4])
        params.setDefaultValue(state[row[0]])
        params.setCancelValue(state[row[0]])
        value = Kernel.pbMessageChooseNumber(_INTL(row[2]), params)
        change(row[0], value)
      end
    end
  end

  def self.open_regions
    loop do
      commands = REGIONS.each_with_index.map do |name, index|
        _INTL("{1}: {2}", name, state["regions"].include?(index + 1) ? "ON" : "OFF")
      end
      commands.push(_INTL("Todas las regiones"), _INTL("Volver"))
      selected = Kernel.pbMessage(_INTL("Region: desactiva las generaciones que no deben aparecer."), commands, commands.length)
      break if selected < 0 || selected >= 10
      if selected == 9
        change("regions", [1,2,3,4,5,6,7,8,9])
      else
        values = state["regions"].clone
        values.include?(selected + 1) ? values.delete(selected + 1) : values.push(selected + 1)
        change("regions", values.sort)
      end
    end
  end

  def self.open_menu
    return if !manage
    begin
      catalog
      apply_tm_moves
    rescue StandardError => error
      Kernel.pbMessage(_INTL("No se pudo cargar el randomizador: {1}", error.message))
      return
    end
    loop do
      commands = [_INTL("Randomizador: {1}", status(state["enabled"]))]
      commands.concat(GROUPS.map { |g| _INTL(g[0]) })
      commands.push(_INTL("Region ({1}/9)", state["regions"].length), _INTL("Volver"))
      chosen = Kernel.pbMessage(_INTL("Randomizador SebiLink\nSalvajes: sorteo nuevo en cada encuentro.\nOpciones del jugador: se guardan al cambiarlas en sebilink.ini."), commands, commands.length)
      if chosen == 0
        if !state["enabled"]
          generate_starters if state["starters"].empty?
        end
        change("enabled", !state["enabled"])
      elsif chosen > 0 && chosen <= GROUPS.length
        open_group(GROUPS[chosen - 1])
      elsif chosen == GROUPS.length + 1
        open_regions
      else
        break
      end
    end
  end

  def self.new_game_setup
    return if !$PokemonGlobal || !$PokemonGlobal.instance_variable_get("@sebi_randomizer_setup_pending")
    $PokemonGlobal.instance_variable_set("@sebi_randomizer_setup_pending", false)
    if Kernel.pbConfirmMessage(_INTL("Quieres configurar y activar el randomizador SebiLink antes de empezar?"))
      change("enabled", true)
      generate_starters
      open_menu
    else
      change("enabled", false)
    end
  end

  def self.generate_starters
    return if !state || !$game_variables || !defined?(RandomizedChallenge)
    return if !state["starter"]
    choices = []
    RandomizedChallenge::STATERS_VARIABLES.each_with_index do |var, i|
      row = choose("starter")
      choices.push([row[0], form_for(row)])
      $game_variables[var] = row[0]
    end
    state["starters"] = choices
    if defined?(SebiLinkFileConfig)
      $PokemonGlobal.instance_variable_get("@sebi_randomizer")["starters"] = choices
    end
  end

  def self.vanilla_starter(index)
    options = {
      238 => [:CHESPIN, :FENNEKIN, :FROAKIE], 239 => [:BULBASAUR, :CHARMANDER, :SQUIRTLE],
      240 => [:CHIKORITA, :CYNDAQUIL, :TOTODILE], 241 => [:TREECKO, :TORCHIC, :MUDKIP],
      242 => [:TURTWIG, :CHIMCHAR, :PIPLUP], 244 => [:SNIVY, :TEPIG, :OSHAWOTT],
      245 => [:ROWLET, :LITTEN, :POPPLIO], 246 => [:GROOKEY, :SCORBUNNY, :SOBBLE],
      247 => [:SPRIGATITO, :FUECOCO, :QUAXLY]}
    chosen = options.keys.sort.find { |key| $game_switches && $game_switches[key] }
    return id(PBSpecies, options[chosen || 238][index])
  end

  def self.constant_ids(mod)
    values = mod.constants.map { |name| mod.const_get(name) }.select { |v| v.is_a?(Integer) && v > 0 }
    return values.uniq.sort
  end

  def self.move_ids
    return @move_ids if @move_ids
    blacklist = defined?(RandomizedChallenge::MOVEBLACKLIST) ? RandomizedChallenge::MOVEBLACKLIST : []
    @move_ids = constant_ids(PBMoves).select { |v| !blacklist.include?(v) && !pbIsHiddenMove?(v) }
    return @move_ids
  end

  def self.random_move(original = nil)
    return original if original && pbIsHiddenMove?(original)
    values = move_ids
    return original if values.empty?
    return values[rand(values.length)]
  end

  def self.attack_move
    @attack_ids ||= move_ids.select { |v| PBMoveData.new(v).basedamage.to_i > 0 }
    return @attack_ids.empty? ? random_move : @attack_ids[rand(@attack_ids.length)]
  end

  def self.ability_ids
    blacklist = defined?(RandomizedChallenge::ABILITYBLACKLIST) ? RandomizedChallenge::ABILITYBLACKLIST : []
    @ability_ids ||= constant_ids(PBAbilities).select { |v| !blacklist.include?(v) }
    return @ability_ids
  end

  def self.protected_item?(item)
    return true if !item || item <= 0 || !$ItemData || !$ItemData[item]
    return true if pbIsKeyItem?(item) || pbIsHiddenMachine?(item) || pbIsMegaStone?(item)
    return true if defined?(RandomizedChallenge::UNRANDOMIZABLE_ITEMS) && RandomizedChallenge::UNRANDOMIZABLE_ITEMS.include?(item)
    return false
  end

  def self.item_pool(held = false)
    key = held ? :held : :all
    @item_pools ||= {}
    return @item_pools[key] if @item_pools[key]
    blacklist = defined?(RandomizedChallenge::ITEM_BLACK_LIST) ? RandomizedChallenge::ITEM_BLACK_LIST : []
    held_blacklist = defined?(RandomizedChallenge::HELD_ITEM_BLACK_LIST) ? RandomizedChallenge::HELD_ITEM_BLACK_LIST : []
    @item_pools[key] = constant_ids(PBItems).select do |v|
      !protected_item?(v) && !blacklist.include?(v) &&
        (!held || (!pbIsMachine?(v) && !held_blacklist.include?(v)))
    end
    return @item_pools[key]
  end

  def self.random_item(item, held = false)
    item = id(PBItems, item)
    return item if protected_item?(item)
    values = item_pool(held)
    return values.empty? ? item : values[rand(values.length)]
  end

  def self.apply_tm_moves
    return if !$ItemData || !state
    if !@original_tms
      @original_tms = {}
      # Always use the compiled originals, even when adopting a vanilla random save.
      originals = readItemList("Data/items.dat")
      originals.each_with_index { |data, item| @original_tms[item] = data[ITEMMACHINE] if data && pbIsTechnicalMachine?(item) }
    end
    $ItemData.each_with_index do |data, item|
      next if !data || !pbIsTechnicalMachine?(item)
      @original_tms[item] ||= data[ITEMMACHINE]
      original = @original_tms[item]
      if active?("tm_moves") && !pbIsHiddenMove?(original)
        state["tm_map"][item] ||= random_move(original)
        data[ITEMMACHINE] = state["tm_map"][item]
      else
        data[ITEMMACHINE] = original
      end
    end
  end

  def self.prepare_pokemon(pokemon)
    return pokemon if !pokemon || !active?
    if active?("abilities")
      values = ability_ids
      pokemon.instance_variable_set("@sebi_randomizer_ability", values[rand(values.length)]) if !values.empty?
    end
    return pokemon
  end

  def self.ensure_attack(pokemon)
    return if !active?("level_moves")
    return if pokemon.moves.any? { |move| move && move.id > 0 && PBMoveData.new(move.id).basedamage.to_i > 0 }
    pokemon.moves[0] = PBMove.new(attack_move)
  end

  def self.normalize_generated_form(pokemon)
    return if !active?("wild") || !pokemon.is_a?(PokeBattle_Pokemon)
    selected = pokemon.instance_variable_get("@sebi_randomizer_wild_form")
    return if selected == nil
    # Native map callbacks and bosses may force regional/custom forms after creation.
    row = catalog.find { |r| r[0] == pokemon.species }
    return if !row
    current = pokemon.form
    allowed = current == 0 || row[4].any? do |f|
      f[0] == current && state["regions"].include?(f[1]) &&
        (f[2] != "r" || state["regional_forms"]) && (f[2] != "c" || state["custom_forms"])
    end
    pokemon.form = selected if !allowed
  end

  def self.random_compatibility?(move)
    return active? && (domain == "tutor" || (active?("tm_moves") && state["tm_map"].values.include?(move)))
  end

  def self.trainer_domain(trainerid)
    value = id(PBTrainers, trainerid)
    PBTrainers.constants.each do |name|
      next if name.to_s !~ /\ALIDER\d+R?\z/
      return "gym" if PBTrainers.const_get(name) == value
    end
    return "trainer"
  end

  def self.finish_trainer(trainer, domain)
    return trainer if !trainer || !active?
    trainer[2].each do |pokemon|
      if active?(domain)
        row = choose(domain)
        replacement = context(nil) { PokeBattle_Pokemon.new(row[0], pokemon.level, trainer[0]) }
        # Keep the trainer's level/IVs/EVs/nature; rebuild species-dependent moves.
        replacement.iv = pokemon.iv.clone
        replacement.ev = pokemon.ev.clone
        replacement.setNature(pokemon.nature)
        replacement.setItem(pokemon.item)
        replacement.makeShiny if pokemon.isShiny?
        replacement.form = form_for(row)
        prepare_pokemon(replacement)
        replacement.resetMoves
        ensure_attack(replacement)
        replacement.calcStats
        replacement.heal
        trainer[2][trainer[2].index(pokemon)] = replacement
        pokemon = replacement
      else
        prepare_pokemon(pokemon)
      end
      pokemon.setItem(random_item(pokemon.item, true)) if active?("trainer_items")
    end
    return trainer
  end

  def self.randomize_existing(pokemon, domain)
    return pokemon if !active?(domain) || !pokemon.is_a?(PokeBattle_Pokemon)
    row = choose(domain)
    level = pokemon.level
    pokemon.species = row[0]
    pokemon.level = level
    pokemon.form = form_for(row)
    pokemon.name = PBSpecies.getName(row[0])
    pokemon.instance_variable_set("@sebi_randomizer_moves", nil)
    prepare_pokemon(pokemon)
    pokemon.resetMoves
    ensure_attack(pokemon)
    pokemon.calcStats
    pokemon.healHP
    return pokemon
  end

  def self.gift_domain(pokemon)
    return domain if domain
    # Most Z NPC swaps remove a party slot then call pbAddPokemon, rather than pbStartTrade.
    interpreter = ($game_system.map_interpreter if $game_system) rescue nil
    while interpreter && interpreter.instance_variable_get("@child_interpreter")
      interpreter = interpreter.instance_variable_get("@child_interpreter")
    end
    if interpreter
      list = interpreter.instance_variable_get("@list")
      index = interpreter.instance_variable_get("@index").to_i
      if list
        nearby = list[[0,index - 6].max, 10] || []
        return "npc_trade" if nearby.any? { |command| command.parameters.any? { |p| p.is_a?(String) && p.include?("pbRemovePokemonAt") } }
      end
    end
    return "fossil" if $PokemonGlobal && $PokemonGlobal.reviving_fossil
    species = pokemon.is_a?(PokeBattle_Pokemon) ? pokemon.species : id(PBSpecies, pokemon)
    name = getConstantName(PBSpecies, species).to_s rescue ""
    # Audited revival events: Map290 and Map307 give these species via pbAddPokemon.
    fossils = %w[KABUTO OMANYTE ANORITH LILEEP AERODACTYL CRANIDOS SHIELDON TIRTOUGA ARCHEN
      TYRUNT AMAURA DRACOZOLT ARCTOZOLT DRACOVISH ARCTOVISH]
    return "fossil" if fossils.include?(name) && $game_map && [290,307].include?($game_map.map_id)
    return "starter" if $game_map && $game_map.map_id == 2 && $Trainer && $Trainer.party.empty?
    return "gift"
  end

  def self.owned_object?(pokemon)
    return true if $Trainer && $Trainer.party.any? { |p| p.equal?(pokemon) }
    if $PokemonStorage
      for box in 0...$PokemonStorage.maxBoxes
        for slot in 0...$PokemonStorage.maxPokemon(box)
          return true if $PokemonStorage[box, slot].equal?(pokemon)
        end
      end
    end
    return false
  end

  def self.evolution_allowed?(species)
    return true if !active? || species.to_i <= 0
    row = catalog.find { |r| r[0] == species.to_i }
    return row && state["regions"].include?(row[1]) && (row[2] != "c" || state["custom_species"])
  end
end

class PokemonGlobalMetadata
  unless method_defined?(:sebi_randomizer_metadata_initialize)
    alias sebi_randomizer_metadata_initialize initialize
    def initialize
      sebi_randomizer_metadata_initialize
      @sebi_randomizer = SebiRandomizer.defaults
      @sebi_randomizer_setup_pending = true
    end
  end
end

class PokeBattle_Pokemon
  unless method_defined?(:sebi_randomizer_initialize)
    alias sebi_randomizer_initialize initialize
    alias sebi_randomizer_getMoveList getMoveList
    alias sebi_randomizer_getAbilityList getAbilityList
    alias sebi_randomizer_move_compatible isCompatibleWithMove?
    def initialize(species, level, player = nil, withMoves = true)
      domain = SebiRandomizer.domain
      row = nil
      row = SebiRandomizer.choose(domain) if domain && SebiRandomizer.active?(domain)
      species = row[0] if row
      sebi_randomizer_initialize(species, level, player, withMoves)
      if domain && SebiRandomizer.active?
        if row
          self.form = SebiRandomizer.form_for(row)
          @sebi_randomizer_wild_form = form if domain == "wild"
        end
        SebiRandomizer.prepare_pokemon(self)
        resetMoves if withMoves
        SebiRandomizer.ensure_attack(self) if withMoves
        calcStats
      end
    end

    def getMoveList
      list = sebi_randomizer_getMoveList
      return list if !SebiRandomizer.active?("level_moves") || list.empty?
      @sebi_randomizer_moves ||= {}
      key = [@species, form]
      if !@sebi_randomizer_moves[key]
        result = list.map { |entry| [entry[0], SebiRandomizer.random_move(entry[1])] }
        # Always have an attacking move at level 1, including early starters.
        result.unshift([1, SebiRandomizer.attack_move])
        @sebi_randomizer_moves[key] = result
      end
      return @sebi_randomizer_moves[key].map { |entry| entry.clone }
    end

    def getAbilityList
      return [[@sebi_randomizer_ability, 0]] if SebiRandomizer.active?("abilities") && @sebi_randomizer_ability
      return random_getAbilityList if SebiRandomizer.state && respond_to?(:random_getAbilityList)
      return sebi_randomizer_getAbilityList
    end

    def isCompatibleWithMove?(move)
      move = SebiRandomizer.id(PBMoves, move)
      return true if SebiRandomizer.random_compatibility?(move)
      return sebi_randomizer_move_compatible(move)
    end
  end
end

class Object
  unless method_defined?(:sebi_randomizer_native_enabled) || private_method_defined?(:sebi_randomizer_native_enabled)
    alias sebi_randomizer_native_enabled random_enabled?
    alias sebi_randomizer_native_enable enable_random
    alias sebi_randomizer_generate_starters generate_random_starters
    alias sebi_randomizer_show_starter show_random_starter_picture
    alias sebi_randomizer_give_starter give_starter_random
    alias sebi_randomizer_wild pbGenerateWildPokemon
    alias sebi_randomizer_trainer pbLoadTrainer
    alias sebi_randomizer_add pbAddPokemon
    alias sebi_randomizer_add_silent pbAddPokemonSilent
    alias sebi_randomizer_egg pbGenerateEgg
    alias sebi_randomizer_trade pbStartTrade
    alias sebi_randomizer_tutor pbMoveTutorChoose
    alias sebi_randomizer_daycare pbDayCareGenerateEgg
    alias sebi_randomizer_load_file pbRgssOpen
    alias sebi_randomizer_evolution pbCheckEvolutionEx

    def random_enabled?
      return false if SebiRandomizer.state
      return sebi_randomizer_native_enabled
    end

    def enable_random
      if SebiRandomizer.state
        SebiRandomizer.change("enabled", true)
        SebiRandomizer.generate_starters
        SebiRandomizer.open_menu
      else
        sebi_randomizer_native_enable
      end
    end

    def generate_random_starters
      return SebiRandomizer.generate_starters if SebiRandomizer.state
      return sebi_randomizer_generate_starters
    end

    def show_random_starter_picture(index = 0, var = nil)
      return sebi_randomizer_show_starter(index, var) if !SebiRandomizer.state
      var ||= RandomizedChallenge::STATERS_VARIABLES[index]
      choice = SebiRandomizer.state["starters"][index]
      species = SebiRandomizer.active?("starter") ? pbGet(var) : SebiRandomizer.vanilla_starter(index)
      pokemon = SebiRandomizer.context(nil) { PokeBattle_Pokemon.new(species, 5, $Trainer) }
      pokemon.form = choice[1] if choice && SebiRandomizer.active?("starter")
      return pbMostrarPkmnAnimado(pokemon, true)
    end

    def give_starter_random(index = 0, var = nil, level = 5)
      return sebi_randomizer_give_starter(index, var, level) if !SebiRandomizer.state
      var ||= RandomizedChallenge::STATERS_VARIABLES[index]
      choice = SebiRandomizer.state["starters"][index]
      species = pbGet(var)
      species = SebiRandomizer.vanilla_starter(index) if !SebiRandomizer.active?("starter")
      pokemon = SebiRandomizer.context(nil) { PokeBattle_Pokemon.new(species, level, $Trainer) }
      pokemon.form = choice[1] if choice && SebiRandomizer.active?("starter")
      SebiRandomizer.prepare_pokemon(pokemon)
      pokemon.resetMoves
      SebiRandomizer.ensure_attack(pokemon)
      return SebiRandomizer.context("starter") { pbAddPokemon(pokemon, level) }
    end

    def pbGenerateWildPokemon(species, level, isroamer = false)
      return SebiRandomizer.context("wild") do
        pokemon = sebi_randomizer_wild(species, level, isroamer)
        SebiRandomizer.normalize_generated_form(pokemon)
        SebiRandomizer.ensure_attack(pokemon)
        pokemon.setItem(SebiRandomizer.random_item(pokemon.item, true)) if SebiRandomizer.active?("wild_items")
        pokemon
      end
    end

    def pbLoadTrainer(trainerid, trainername, partyid = 0)
      trainer = SebiRandomizer.context(nil) { sebi_randomizer_trainer(trainerid, trainername, partyid) }
      return SebiRandomizer.finish_trainer(trainer, SebiRandomizer.trainer_domain(trainerid))
    end

    def pbAddPokemon(pokemon, level = nil, seeform = true)
      domain = SebiRandomizer.gift_domain(pokemon)
      if pokemon.is_a?(PokeBattle_Pokemon) && !SebiRandomizer.domain && !SebiRandomizer.owned_object?(pokemon)
        SebiRandomizer.randomize_existing(pokemon, domain)
      end
      begin
        return SebiRandomizer.context(domain) { sebi_randomizer_add(pokemon, level, seeform) }
      ensure
        $PokemonGlobal.reviving_fossil = nil if domain == "fossil" && $PokemonGlobal
      end
    end

    def pbAddPokemonSilent(pokemon, level = nil, seeform = true)
      domain = SebiRandomizer.gift_domain(pokemon)
      if pokemon.is_a?(PokeBattle_Pokemon) && !SebiRandomizer.domain && !SebiRandomizer.owned_object?(pokemon)
        SebiRandomizer.randomize_existing(pokemon, domain)
      end
      return SebiRandomizer.context(domain) { sebi_randomizer_add_silent(pokemon, level, seeform) }
    end

    def pbGenerateEgg(pokemon, text = "")
      if pokemon.is_a?(PokeBattle_Pokemon) && !SebiRandomizer.domain && !SebiRandomizer.owned_object?(pokemon)
        SebiRandomizer.randomize_existing(pokemon, "gift")
      end
      return SebiRandomizer.context(SebiRandomizer.domain || "gift") { sebi_randomizer_egg(pokemon, text) }
    end

    def pbStartTrade(index, pokemon, nickname, name, gender = 0)
      # SebiLink donations pass an already generated object and use their own filter.
      if !pokemon.is_a?(PokeBattle_Pokemon) && SebiRandomizer.active?("npc_trade")
        row = SebiRandomizer.choose("npc_trade")
        pokemon = SebiRandomizer.context(nil) { PokeBattle_Pokemon.new(row[0], $Trainer.party[index].level, $Trainer) }
        pokemon.form = SebiRandomizer.form_for(row)
        SebiRandomizer.prepare_pokemon(pokemon)
        pokemon.resetMoves
        SebiRandomizer.ensure_attack(pokemon)
        nickname = PBSpecies.getName(row[0])
      end
      return SebiRandomizer.context("npc_trade") { sebi_randomizer_trade(index, pokemon, nickname, name, gender) }
    end

    def pbMoveTutorChoose(move, movelist = nil, bymachine = false)
      if !bymachine && SebiRandomizer.active?("tutor_moves")
        move = SebiRandomizer.random_move(SebiRandomizer.id(PBMoves, move))
        movelist = nil
        return SebiRandomizer.context("tutor") { sebi_randomizer_tutor(move, movelist, bymachine) }
      end
      return sebi_randomizer_tutor(move, movelist, bymachine)
    end

    def pbDayCareGenerateEgg
      return SebiRandomizer.context(nil) { sebi_randomizer_daycare }
    end

    def pbCheckEvolutionEx(pokemon, &block)
      species = sebi_randomizer_evolution(pokemon, &block)
      return SebiRandomizer.evolution_allowed?(species) ? species : -1
    end

    def pbRgssOpen(file, mode = nil, &block)
      result = sebi_randomizer_load_file(file, mode)
      if file.to_s.gsub("\\", "/") =~ /eggEmerald\.dat\z/i && SebiRandomizer.active?("egg_moves")
        class << result
          alias sebi_randomizer_fgetw fgetw unless method_defined?(:sebi_randomizer_fgetw)
          def fgetw
            original = sebi_randomizer_fgetw
            return original if !SebiRandomizer.active?("egg_moves")
            mapping = SebiRandomizer.state["egg_map"]
            mapping[original] ||= SebiRandomizer.random_move(original)
            return mapping[original]
          end
        end
      end
      return result if !block
      begin
        return block.call(result)
      ensure
        result.close
      end
    end
  end

  unless method_defined?(:sebi_randomizer_compatible) || private_method_defined?(:sebi_randomizer_compatible)
    # Machine/tutor random attacks must remain learnable even if compatibility was vanilla.
    alias sebi_randomizer_compatible pbSpeciesCompatible?
    def pbSpeciesCompatible?(species, move)
      return true if SebiRandomizer.random_compatibility?(move)
      return sebi_randomizer_compatible(species, move)
    end
  end
end

module Kernel
  class << self
    unless method_defined?(:sebi_randomizer_item_ball)
      alias sebi_randomizer_item_ball pbItemBall
      alias sebi_randomizer_receive_item pbReceiveItem
      def pbItemBall(item, quantity = 1)
        item = SebiRandomizer.random_item(item) if SebiRandomizer.active?("ground_items")
        return sebi_randomizer_item_ball(item, quantity)
      end
      def pbReceiveItem(item, quantity = 1)
        item = SebiRandomizer.random_item(item) if SebiRandomizer.active?("reward_items")
        return sebi_randomizer_receive_item(item, quantity)
      end
    end
  end
end

class Object
  unless method_defined?(:sebi_randomizer_mart) || private_method_defined?(:sebi_randomizer_mart)
    alias sebi_randomizer_mart pbPokemonMart
    def pbPokemonMart(stock, speech = nil, cantsell = false)
      previous = SebiRandomizer.instance_variable_get("@shop_prices")
      values = stock.clone.map { |item| SebiRandomizer.id(PBItems, item) }
      values = values.map { |item| SebiRandomizer.random_item(item) }.uniq if SebiRandomizer.active?("shop_items")
      prices = {}
      if SebiRandomizer.active?("shop_prices")
        s = SebiRandomizer.state
        values.each do |item|
          prices[item] = s["price_min"] + rand(s["price_max"] - s["price_min"] + 1) if !SebiRandomizer.protected_item?(item)
        end
      end
      SebiRandomizer.instance_variable_set("@shop_prices", prices)
      begin
        return sebi_randomizer_mart(values, speech, cantsell)
      ensure
        SebiRandomizer.instance_variable_set("@shop_prices", previous)
      end
    end
  end
end

class PokemonMartAdapter
  unless method_defined?(:sebi_randomizer_price)
    alias sebi_randomizer_price getPrice
    def getPrice(item, selling = false)
      prices = SebiRandomizer.instance_variable_get("@shop_prices")
      return prices[item] if !selling && SebiRandomizer.active?("shop_prices") && prices && prices[item]
      return sebi_randomizer_price(item, selling)
    end
  end
end

class PokemonLoad
  unless method_defined?(:sebi_randomizer_load_screen)
    alias sebi_randomizer_load_screen pbStartLoadScreen
    def pbStartLoadScreen(*args)
      result = sebi_randomizer_load_screen(*args)
      SebiRandomizer.apply_tm_moves
      SebiRandomizer.new_game_setup
      return result
    end
  end
end

if defined?(SebiSpecialActions)
  module SebiSpecialActions
    class << self
      unless method_defined?(:sebi_randomizer_trade_allowed)
        alias sebi_randomizer_trade_allowed trade_species_allowed?
        def trade_species_allowed?(species, unavailable = nil)
          return false if !sebi_randomizer_trade_allowed(species, unavailable)
          return true if !SebiRandomizer.active?
          row = SebiRandomizer.catalog.find { |r| r[0] == species.to_i }
          return row && SebiRandomizer.allowed?(row, "donation")
        end
      end
    end
  end
end

if defined?(SebiVisualMultiplayer)
  module SebiVisualMultiplayer
    class << self
      unless method_defined?(:sebi_randomizer_battle_flow)
        alias sebi_randomizer_battle_flow start_battle_flow
        alias sebi_randomizer_snapshot_battle start_snapshot_battle
        def start_battle_flow(*args)
          return SebiRandomizer.suspend { sebi_randomizer_battle_flow(*args) }
        end
        def start_snapshot_battle(*args)
          return SebiRandomizer.suspend { sebi_randomizer_snapshot_battle(*args) }
        end
      end
    end
  end
end

if defined?(SebiPvpRules)
  module SebiPvpRules
    class << self
      unless method_defined?(:sebi_randomizer_prepare_party)
        alias sebi_randomizer_prepare_party prepare_party
        def prepare_party(*args)
          return SebiRandomizer.suspend { sebi_randomizer_prepare_party(*args) }
        end
      end
    end
  end
end

if defined?(SebiSaveManager)
  module SebiSaveManager
    class << self
      unless method_defined?(:sebi_randomizer_reset_save)
        alias sebi_randomizer_reset_save reset_windows_after_restore
        def reset_windows_after_restore
          result = sebi_randomizer_reset_save
          SebiRandomizer.apply_tm_moves
          return result
        end
      end
    end
  end
end

if defined?(Events) && !SebiRandomizer.instance_variable_get("@battle_form_hook_installed")
  Events.onStartBattle += proc { |sender, data|
    pokemon = data[0] if data
    SebiRandomizer.normalize_generated_form(pokemon)
    SebiRandomizer.ensure_attack(pokemon) if pokemon.is_a?(PokeBattle_Pokemon)
  }
  SebiRandomizer.instance_variable_set("@battle_form_hook_installed", true)
end
