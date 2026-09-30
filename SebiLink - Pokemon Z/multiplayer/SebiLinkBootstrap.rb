# SebiLink for Pokemon Z V2.18 / Windows MKXP.
# Runs via mkxp.json preloadScript before the decoded game scripts execute.
# Keep the array length unchanged: MKXP caches its length before preloading.
module SebiLinkBootstrap
  LOADER_NAME = "Sebi Visual Multiplayer Loader"
  MENU_MARKER = "# SebiPokeLink hub menu option"
  MENU_PATCH = <<'RUBY'
    # SebiPokeLink hub menu option
    if defined?(SebiPokeLinkMenu)
      @options << ["SebiLink", "optionsA", "optionsB", proc {
        pbFadeOutIn(99999) do
          SebiPokeLinkMenu.open_menu
          pbUpdateSceneMap
        end
      }]
    end

RUBY
  LOADER = <<'RUBY'
# SebiLink portable loader
load "multiplayer/SebiVisualMultiplayer.rb"

RUBY

  def self.apply(scripts)
    raise "SebiLink: este paquete necesita Pokemon Z V2.18 con MKXP." unless scripts.is_a?(Array)
    menus = scripts.select { |row| row.is_a?(Array) && row[1] == "Menu Mejorado" }
    mains = scripts.select { |row| row.is_a?(Array) && row[1] == "Main" }
    raise "SebiLink: no se encuentran los scripts de Pokemon Z V2.18." unless menus.length == 1 && mains.length == 1
    menu = menus[0]
    main = mains[0]
    raise "SebiLink: MKXP no ha decodificado los scripts." unless menu[3].is_a?(String) && main[3].is_a?(String)
    menu_text = menu[3]
    main_text = main[3]
    unless menu_text.include?(MENU_MARKER)
      anchor = /^[ \t]*@count = @options\.size[ \t]*\r?$/
      raise "SebiLink: menu incompatible; no se ha aplicado ningun parche." unless menu_text.scan(anchor).length == 1
      menu_text = menu_text.sub(anchor) { |line| MENU_PATCH + line }
    end
    unless scripts.any? { |row| row.is_a?(Array) && row[1] == LOADER_NAME } || main_text.include?("# SebiLink portable loader")
      main_text = LOADER + main_text
    end
    # Only decoded strings change; original compressed data and files stay intact.
    menu[3] = menu_text
    main[3] = main_text
    return true
  end
end

SebiLinkBootstrap.apply(defined?($RGSS_SCRIPTS) ? $RGSS_SCRIPTS : nil)
