# Complete, public catalogue of player preferences. No personal values in this file.
module SebiSettingsRegistry
  BASE_DEFAULTS = {
    "multiplayer_enabled" => false, "multiplayer_mode" => "",
    "multiplayer_host" => "127.0.0.1", "multiplayer_port" => 54545,
    "multiplayer_send_interval" => 3, "multiplayer_remote_smoothing" => 2,
    "multiplayer_connect_timeout_frames" => 300, "multiplayer_retry_frames" => 600,
    "multiplayer_fade_after" => 180, "multiplayer_hide_after" => 600,
    "multiplayer_pvp_wait_frames" => 108000, "multiplayer_debug" => false,
    "create_host" => "", "create_port" => "", "join_host" => "", "join_port" => "",
    "player_name" => "Player", "remote_collisions" => true,
    "battle_weakness_overlay" => false, "party_weakness_overlay" => false,
    "extra_control_pokemondb" => 114, "extra_control_weakness" => 115,
    "extra_control_level_sync" => 117,
    "wild_shiny_percent" => 10, "level_cap_override" => "",
    "level_cap_default_extra" => 2, "max_repel" => false, "sacred_ashes_quantity" => 2,
    "pvp_team_source" => "current", "pvp_level_rule" => "current", "pvp_monotype" => -1,
    "pvp_legend_count" => 0, "pvp_iv_rule" => "default", "pvp_iv_custom" => 31,
    "pvp_ev_rule" => "default", "pvp_ev_custom" => 85, "pvp_item_rule" => "default",
    "pvp_move_rule" => "default", "pvp_mega_rule" => "default", "pvp_saved_team" => "",
    "pvp_format" => "single", "training_mode" => "dummy", "training_species" => "WOBBUFFET",
    "training_saved_team" => "", "training_use_attacks" => false,
    "codex_ai_host" => "127.0.0.1", "codex_ai_user" => "root",
    "codex_ai_remote_dir" => "/root/codexray-requests", "codex_ai_workdir" => "/root",
    "codex_ai_model" => "", "codex_ai_reasoning" => "medium", "codex_ai_timeout_seconds" => 180,
    "codex_ai_bridge_script" => "", "codex_ai_sebilink_skill" => "",
    "hub_topmost" => false, "save_manager_topmost" => false,
    "save_editor_auto_refresh" => false, "save_editor_bag_owned_only" => true
  }
  # Same order and keyboard defaults as Pokemon Z's original Keys.defaultControls.
  CONTROL_DEFAULTS = [40,37,39,38,67,13,88,27,90,18,116,34,33,65,83,68]

  def self.defaults
    result = BASE_DEFAULTS.clone
    CONTROL_DEFAULTS.each_with_index { |key, index| result["control_" + index.to_s] = key }
    for slot in 1..9
      result["quick_save_slot_" + slot.to_s + "_path"] = ""
      result["quick_save_slot_" + slot.to_s + "_key"] = 0
    end
    if defined?(SebiRandomizer)
      SebiRandomizer.defaults.each do |key, value|
        next if %w[tm_map egg_map starters revision].include?(key)
        result["randomizer_" + key] = key == "regions" ? value.join(",") : value
      end
    end
    return result
  end

  def self.initialize_all
    SebiLinkFileConfig.fill_defaults(defaults)
  end
end
