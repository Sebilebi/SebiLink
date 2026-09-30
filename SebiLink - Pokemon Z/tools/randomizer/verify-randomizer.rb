# Offline integration tests: real compiled enums, dex/move/item data, Pokemon,
# MultipleForms and RandomMain. UI/map/battle presentation is stubbed; no Game.exe.
require 'zlib'
require 'stringio'
require 'csv'
GAME = File.expand_path('../..', __dir__)
Dir.chdir(GAME)
scripts = Marshal.load(File.binread('Data/Scripts.rxdata')).to_h { |row| [row[1], Zlib::Inflate.inflate(row[2]).force_encoding('UTF-8')] }
Marshal.load(File.binread('Data/Constants.rxdata')).each { |row| eval(Zlib::Inflate.inflate(row[2]), TOPLEVEL_BINDING, row[1]) }
def _INTL(text, *args); args.each_with_index { |v,i| text = text.gsub("{#{i+1}}",v.to_s) }; text; end
def getID(mod, value)
  return value if value.is_a?(Integer)
  mod.const_get(value.to_s) rescue 0
end
def getConst(mod, value); getID(mod, value); end
def hasConst?(mod, value); getID(mod, value) > 0; end
def isConst?(value, mod, name); value == getID(mod, name); end
def getConstantName(mod, value); mod.constants.find { |c| mod.const_get(c) == value }.to_s; end
def pbGetMessage(_kind, value); value.to_s; end
module MessageTypes
  def self.const_missing(name); const_set(name, name); end
end
def pbGetTimeNow; Time.now; end
def pbGetEnvironment; 0; end
MetadataOutdoor=1
def pbGetMetadata(*_args); true; end
def pbSeenForm(*_args); end
def pbRgssOpen(file, mode = nil, &block)
  return File.open(file, mode || 'rb', &block)
end
class StringInput < StringIO
  def self.open(string)
    io = new(string)
    return io if !block_given?
    begin; yield io; ensure; io.close; end
  end
end
eval(scripts.fetch('File_Mixins'), TOPLEVEL_BINDING, 'File_Mixins')
class StringInput
  def each_byte
    yield read(1).unpack('C')[0] until eof?
  end
end
eval(scripts.fetch('Settings'), TOPLEVEL_BINDING, 'Settings')
%w[PBExperience PBStats PBMove PBEnvironment PokeBattle_Pokemon].each { |name| eval(scripts.fetch(name), TOPLEVEL_BINDING, name) }
def pbOpenDexData; StringInput.open(File.binread('Data/dexdata.dat')); end
def pbDexDataOffset(data, species, offset); data.pos = 76 * (species - 1) + offset; end
def pbSpeciesCompatible?(_species, _move); false; end
class HandlerHash
  def initialize(mod); @mod = Object.const_get(mod); @data = {}; end
  def add(key,value); @data[getID(@mod,key)] = value; end
  def [](key); @data[key]; end
  def copy(key,*targets); targets.each { |target| add(target,self[getID(@mod,key)]) }; end
  def addIf(*_args); end
end
eval(scripts.fetch('Pokemon_MultipleForms'), TOPLEVEL_BINDING, 'Pokemon_MultipleForms')
class PokemonGlobalMetadata
  attr_accessor :reviving_fossil
  def initialize; end
end
class PokemonLoad
  def pbStartLoadScreen(*_args); :loaded; end
end
class PokemonMartAdapter
  def getPrice(item, _selling=false); $ItemData[item][4]; end
end
class PokemonEncounters
  def setup(*_args); end
  def pbEncounteredPokemon(*_args); end
end
class EncounterListUI
  def pbListOfEncounters(*_args); []; end
end
class PokemonEvolutionScene
  def pbEvolution(*_args); end
end
module Kernel
  class << self
    attr_accessor :answers, :messages, :confirm_answer
    def pbMessage(text, commands=nil, _cancel=nil, *_options)
      (@messages ||= []) << [text, commands]
      return nil if !commands
      answer = (@answers ||= []).shift
      return answer.nil? ? commands.length - 1 : answer
    end
    def pbConfirmMessage(_text); @confirm_answer == true; end
    def pbItemBall(item, quantity=1); [item,quantity]; end
    def pbReceiveItem(item, quantity=1); [item,quantity]; end
  end
end
class TrainerStub
  attr_accessor :party, :name, :id, :gender, :language
  def initialize; @party=[]; @name='Offline'; @id=42; @gender=0; @language=1; end
  def numbadges; 0; end
  def secretID; @id >> 16; end
end
def pbRgssExists?(path); File.exist?(path); end
# Evaluate only read-only serialization declarations, never Compiler's startup block.
compiler = scripts.fetch('Compiler')
eval(compiler[/^def intSize.*?(?=^def pbGetConst)/m], TOPLEVEL_BINDING, 'Compiler serialization')
eval(compiler[/^class SerialRecord < Array.*?(?=^def readSerialRecords)/m], TOPLEVEL_BINDING, 'Compiler SerialRecord')
eval(compiler[/^class ItemList.*?(?=^def pbCompileItems)/m], TOPLEVEL_BINDING, 'Compiler ItemList')
ITEMMACHINE = 9
ITEMPRICE = 4
ITEMUSE = 6
def pbIsTechnicalMachine?(item); $ItemData[item] && $ItemData[item][6] == 3; end
def pbIsHiddenMachine?(item); $ItemData[item] && $ItemData[item][6] == 4; end
def pbIsMachine?(item); pbIsTechnicalMachine?(item) || pbIsHiddenMachine?(item); end
def pbIsKeyItem?(item); $ItemData[item] && $ItemData[item][8] == 6; end
def pbIsMegaStone?(item); getConstantName(PBItems,item) =~ /ITE[XY]?\z/; end
def pbIsHiddenMove?(move); $ItemData.any? { |row| row && row[6] == 4 && row[9] == move }; end
def pbAddPokemon(pokemon, level=nil, _seeform=true)
  pokemon = PokeBattle_Pokemon.new(pokemon,level,$Trainer) if !pokemon.is_a?(PokeBattle_Pokemon)
  $Trainer.party << pokemon
  pokemon
end
def pbAddPokemonSilent(*args); pbAddPokemon(*args); end
def pbGenerateEgg(pokemon, _text=''); pbAddPokemon(pokemon,EGGINITIALLEVEL); end
def pbGenerateWildPokemon(species,level,_roamer=false); PokeBattle_Pokemon.new(species,level,$Trainer); end
class EventHook
  def initialize; @handlers=[]; end
  def +(handler); @handlers << handler; self; end
  def trigger(sender,*data); @handlers.each { |h| h.call(sender,data) }; end
end
module Events
  class << self
    attr_accessor :onWildPokemonCreate, :onStartBattle
  end
  self.onWildPokemonCreate=EventHook.new
  self.onStartBattle=EventHook.new
end
class TrainerStub
  def firstParty; @party.find { |p| !p.isEgg? }; end
end
class BagStub
  def pbQuantity(_item); 0; end
end
$PokemonBag=BagStub.new
# Exercise the real creation path, including map-specific form callbacks.
eval(scripts.fetch('PField_Field')[/^def pbGenerateWildPokemon.*?(?=^def pbWildBattle)/m], TOPLEVEL_BINDING, 'PField_Field wild')
eval(scripts.fetch('PField_EncounterModifiers'), TOPLEVEL_BINDING, 'PField_EncounterModifiers')
def pbLoadTrainer(_id,_name,_party=0)
  rival = TrainerStub.new
  [rival, [], [PokeBattle_Pokemon.new(PBSpecies::PIKACHU,20,rival)]]
end
def pbStartTrade(index,pokemon,_nickname,_name,_gender=0)
  pokemon = PokeBattle_Pokemon.new(pokemon,10,$Trainer) if !pokemon.is_a?(PokeBattle_Pokemon)
  $Trainer.party[index] = pokemon
  pokemon
end
def pbMoveTutorChoose(move,_list=nil,_machine=false)
  [move, $Trainer.party.first.isCompatibleWithMove?(move)]
end
def pbDayCareGenerateEgg; pbRgssOpen('Data/eggEmerald.dat','rb') { |f| f.pos=8*PBSpecies.maxValue; f.fgetw }; end
def pbBossFight(*_args); end
def pbGet(var); $game_variables[var]; end
def pbMostrarPkmnAnimado(pokemon,_bg); pokemon; end
def enable_random_items; end
def random_held_items_enabled?; false; end
def pbPokemonMart(stock,_speech=nil,_cantsell=false)
  adapter=PokemonMartAdapter.new
  stock.map { |item| [item,adapter.getPrice(item),adapter.getPrice(item,true)] }
end
eval(scripts.fetch('PField_Encounters'), TOPLEVEL_BINDING, 'PField_Encounters')
eval(scripts.fetch('RandomMain'), TOPLEVEL_BINDING, 'RandomMain')
$game_switches = Hash.new(false)
$game_variables = Hash.new(0)
$PokemonGlobal = PokemonGlobalMetadata.new
$PokemonStorage = nil
$PokemonTemp = nil
$Trainer = TrainerStub.new
$ItemData = readItemList('Data/items.dat')
$game_map = Struct.new(:map_id).new(1)
module SebiVisualMultiplayer
  def self.start_battle_flow(*_args); SebiRandomizer.active?; end
  def self.start_snapshot_battle(*_args); SebiRandomizer.active?; end
end
module SebiPvpRules
  def self.prepare_party(*_args); SebiRandomizer.active?; end
end
module SebiSpecialActions
  def self.trade_species_allowed?(_species,_unavailable=nil); true; end
end
module SebiSaveManager
  def self.reset_windows_after_restore; true; end
end
load 'multiplayer/SebiRandomizer.rb'

def assert(condition, label)
  raise "FAILED: #{label}" if !condition
  $checks = $checks.to_i + 1
end
def reset_save
  $PokemonGlobal = PokemonGlobalMetadata.new
  $Trainer = TrainerStub.new
  $game_map.map_id = 1
  SebiRandomizer.manage
end
reset_save
menu_group = SebiRandomizer::GROUPS.find { |g| g[1].any? { |row| row.length == 3 } }
menu_option = menu_group[1].index { |row| row.length == 3 }
menu_key = menu_group[1][menu_option][0]
menu_before = SebiRandomizer.state[menu_key]
Kernel.messages = []
Kernel.answers = [menu_option, menu_group[1].length]
SebiRandomizer.open_group(menu_group)
assert(SebiRandomizer.state[menu_key] == !menu_before, 'one click toggles boolean without a second choice')
assert(Kernel.messages.length == 2, 'toggle immediately returns to the updated option list')
Kernel.answers = [menu_option, menu_group[1].length]
SebiRandomizer.open_group(menu_group)
assert(SebiRandomizer.state[menu_key] == menu_before, 'next click toggles the same option back')
srand(24680)
assert(SebiRandomizer.catalog.length == 1016, 'all available species classified (placeholder excluded)')
assert(!SebiRandomizer.active?, 'new games start disabled until user chooses')
assert(!random_enabled?, 'managed settings suppress vanilla random hooks')
SebiRandomizer.change('enabled',true)
assert(SebiRandomizer.active?, 'master enabled')
assert(!SebiRandomizer.state['progression'], 'full random is default, no hidden BST cap')
assert(!SebiRandomizer.state['custom_species'], 'custom species disabled by default')
assert(!SebiRandomizer.state['regional_forms'], 'regional forms disabled by default')
SebiRandomizer.change('regions',[1])
samples = 800.times.map { pbGenerateWildPokemon(PBSpecies::PIKACHU,5).species }
allowed = SebiRandomizer.pool('wild').map(&:first)
assert(samples.all? { |id| allowed.include?(id) }, 'each wild encounter respects Kanto only')
assert(samples.uniq.length > 130, 'same route/input rerolls instead of mapping species')
assert(samples.any? { |id| id == PBSpecies::MEWTWO }, 'final stages and legends allowed from level 5')
SebiRandomizer.change('wild_legendary',false)
SebiRandomizer.change('wild_mythical',false)
assert(!SebiRandomizer.pool('wild').any? { |r| %w[l m].include?(r[2]) }, 'legendary and mythical exclusions')
assert(!SebiRandomizer.change('regions',[]), 'cannot disable the final region')
assert(SebiRandomizer.state['regions']==[1], 'invalid changes preserve previous settings')
SebiRandomizer.change('regions',[1,2,3,4,5,6,7,8,9])
SebiRandomizer.change('custom_species',true)
assert(SebiRandomizer.pool('wild').any? { |r| r[2]=='c' }, 'custom evolutions/species can be enabled')
SebiRandomizer.change('custom_species',false)
assert(!SebiRandomizer.pool('wild').any? { |r| r[2]=='c' }, 'custom species filtered independently')
raichu = SebiRandomizer.catalog.find { |r| r[0]==PBSpecies::RAICHU }
dugtrio = SebiRandomizer.catalog.find { |r| r[0]==PBSpecies::DUGTRIO }
assert(30.times.all? { SebiRandomizer.form_for(raichu)==0 }, 'regional OFF')
SebiRandomizer.change('regional_forms',true)
assert(30.times.map { SebiRandomizer.form_for(raichu) }.include?(1), 'regional ON')
assert(30.times.all? { SebiRandomizer.form_for(dugtrio)==0 }, 'custom Dugtrio not mistaken for Alola')
SebiRandomizer.change('custom_forms',true)
assert(30.times.map { SebiRandomizer.form_for(dugtrio) }.include?(1), 'custom forms ON')
SebiRandomizer.change('regions',[1])
assert(30.times.all? { SebiRandomizer.form_for(raichu)==0 }, 'Alola disabled also excludes its forms')
SebiRandomizer.change('regions',[1,2,3,4,5,6,7,8,9])
SebiRandomizer.change('progression',true)
assert(SebiRandomizer.pool('wild').all? { |r| r[3]==0 }, 'progression restricts stage at low party level')
SebiRandomizer.change('progression',false)
SebiRandomizer.change('wild',false)
assert(pbGenerateWildPokemon(PBSpecies::PIKACHU,5).species==PBSpecies::PIKACHU, 'wild OFF restores original species')
SebiRandomizer.change('trainer',false)
assert(pbLoadTrainer(:CAMPESINO,'Offline')[2][0].species==PBSpecies::PIKACHU, 'trainer OFF')
rivals = 30.times.map { pbLoadTrainer(:LIDER1,'Offline')[2][0] }
assert(rivals.map(&:species).uniq.length>10, 'gym independent from trainer switch')
assert(rivals.all? { |p| p.level==20 && p.hp==p.totalhp }, 'trainer level and full HP preserved')
SebiRandomizer.change('abilities',true)
SebiRandomizer.change('wild',true)
p = pbGenerateWildPokemon(PBSpecies::PIKACHU,5)
ability=p.ability
assert(30.times.all? { p.ability==ability }, 'ability stable per individual')
SebiRandomizer.change('level_moves',true)
p = pbGenerateWildPokemon(PBSpecies::PIKACHU,5)
assert(p.moves.any? { |m| m.id>0 && PBMoveData.new(m.id).basedamage>0 }, 'new wild has attacking move')
list=p.getMoveList
assert(list==p.getMoveList, 'movepool stable across reads')
saved=Marshal.dump([$PokemonGlobal,p])
$PokemonGlobal,p=Marshal.load(saved)
assert(list==p.getMoveList && p.ability>0, 'settings and individual modifiers survive Marshal round trip')
SebiRandomizer.change('tm_moves',true)
tm = (0...$ItemData.length).find { |i| pbIsTechnicalMachine?(i) }
tm_attack=$ItemData[tm][9]
SebiRandomizer.apply_tm_moves
assert(tm_attack==$ItemData[tm][9], 'MT mapping stable')
original_tms=readItemList('Data/items.dat')
hm=(0...$ItemData.length).find { |i| pbIsHiddenMachine?(i) }
assert(!hm || $ItemData[hm][9]==original_tms[hm][9], 'MO preserved')
SebiRandomizer.change('tm_moves',false)
assert($ItemData[tm][9]==original_tms[tm][9], 'MT originals restored on disable')
assert(!SebiVisualMultiplayer.start_battle_flow && !SebiVisualMultiplayer.start_snapshot_battle && !SebiPvpRules.prepare_party, 'PvP preparation and battle suspend story rules')
assert(SebiRandomizer.active?, 'PvP restores suspension after return')
begin; SebiRandomizer.suspend { raise 'test' }; rescue RuntimeError; end
assert(SebiRandomizer.active?, 'suspension restored after exceptions')
SebiRandomizer.change('tutor_moves',true)
$Trainer.party=[p]
assert(pbMoveTutorChoose(PBMoves::TACKLE)[1], 'random tutor move learnable')
SebiRandomizer.change('ground_items',true)
SebiRandomizer.change('reward_items',true)
key=(0...$ItemData.length).find { |i| pbIsKeyItem?(i) }
assert(Kernel.pbItemBall(key)==[key,1] && Kernel.pbReceiveItem(key)==[key,1], 'story key items preserved')
received=40.times.map { Kernel.pbItemBall(PBItems::POTION)[0] }
assert(received.uniq.length>15, 'ground items reroll')
SebiRandomizer.change('shop_prices',true)
visits=2.times.map { pbPokemonMart([PBItems::POTION,PBItems::POKEBALL]) }
assert(visits.flatten(1).all? { |r| r[1]>=100 && r[1]<=10000 }, 'prices honor range')
assert(PokemonMartAdapter.new.getPrice(PBItems::POTION)==$ItemData[PBItems::POTION][4], 'prices restored outside store')
SebiRandomizer.change('price_min',9000)
assert(!SebiRandomizer.change('price_max',8000), 'invalid price range rejected')
SebiRandomizer.change('egg_moves',true)
def egg_move_sample
  pbRgssOpen('Data/eggEmerald.dat','rb') do |f|
    f.pos=(PBSpecies::BULBASAUR-1)*8
    offset=f.fgetdw
    length=f.fgetdw
    f.pos=offset
    [length,f.fgetw]
  end
end
a=egg_move_sample
assert(a==egg_move_sample && a[0]>0 && a[1]>0, 'egg move mapping stable; header offsets intact')
SebiRandomizer.change('starter',true)
SebiRandomizer.generate_starters
preview=show_random_starter_picture(0)
$Trainer.party=[]
given=give_starter_random(0)
assert(preview.species==given.species && preview.form==given.form, 'starter preview equals received Pokemon')
SebiRandomizer.change('fossil',false)
$game_map.map_id=290
assert(pbAddPokemon(:KABUTO,50).species==PBSpecies::KABUTO, 'fossil OFF independent of gifts')
SebiRandomizer.change('fossil',true)
fossils=20.times.map { pbAddPokemon(:KABUTO,50).species }
assert(fossils.uniq.length>10, 'fossil rerolls per revival')
$game_map.map_id=1
SebiRandomizer.change('gift',false)
assert(pbAddPokemon(:PIKACHU,5).species==PBSpecies::PIKACHU, 'gifts OFF')
SebiRandomizer.change('npc_trade',true)
swaps=20.times.map { pbStartTrade(0,:PIKACHU,'Pika','Offline').species }
assert(swaps.uniq.length>10, 'NPC receives new species per trade')
first_save=$PokemonGlobal
SebiRandomizer.change('regions',[1])
reset_save
SebiRandomizer.change('enabled',true)
SebiRandomizer.change('regions',[9])
assert(SebiRandomizer.pool('wild').all? { |r| r[1]==9 }, 'second save uses its own filters')
$PokemonGlobal=first_save
assert(SebiRandomizer.pool('wild').all? { |r| r[1]==1 }, 'returning to first save restores its own pool')
assert(!SebiRandomizer.evolution_allowed?(PBSpecies::AURETOSK), 'disabled custom evolutions cannot be produced')
assert(!SebiRandomizer.evolution_allowed?(PBSpecies::ROSERADE), 'disabled generation excluded from evolution')
SebiRandomizer.change('regions',[1,2,3,4,5,6,7,8,9])
SebiRandomizer.change('regional_forms',false)
exeggutor=SebiRandomizer.context('wild') { PokeBattle_Pokemon.new(PBSpecies::EXEGGUTOR,20,$Trainer) }
# Pin original species to exercise the exact native Alola forcing map callback.
exeggutor.species=PBSpecies::EXEGGUTOR
exeggutor.form=0
exeggutor.instance_variable_set(:@sebi_randomizer_wild_form,0)
$game_map.map_id=230
Events.onWildPokemonCreate.trigger(nil,exeggutor)
assert(exeggutor.form==1, 'test covers native Alola map callback')
Events.onStartBattle.trigger(nil,exeggutor)
assert(exeggutor.form==0, 'regional OFF defeats native form override before battle')
$game_map.map_id=1
command=Struct.new(:parameters)
interpreter=Object.new
interpreter.instance_variable_set(:@list,[command.new(['pbRemovePokemonAt(0)']),command.new(['pbAddPokemon(:PIKACHU,5)'])])
interpreter.instance_variable_set(:@index,1)
$game_system=Struct.new(:map_interpreter).new(interpreter)
assert(SebiRandomizer.gift_domain(:PIKACHU)=='npc_trade','real Z remove/add NPC exchanges use NPC category')
$game_system=nil
SebiRandomizer.change('tm_moves',true)
tm_copy=$ItemData[tm][9]
$PokemonGlobal=PokemonGlobalMetadata.new
SebiSaveManager.reset_windows_after_restore
assert($ItemData[tm][9]==original_tms[tm][9], 'switching saves restores original MT data')
$PokemonGlobal=first_save
SebiSaveManager.reset_windows_after_restore
assert($ItemData[tm][9]==tm_copy, 'switching back restores that save MT mapping')
SebiRandomizer.change('enabled',false)
assert(pbGenerateWildPokemon(PBSpecies::PIKACHU,5).species==PBSpecies::PIKACHU, 'master OFF restores wild generation')
reset_save
Kernel.confirm_answer=false
SebiRandomizer.new_game_setup
assert(!SebiRandomizer.active? && !$PokemonGlobal.instance_variable_get(:@sebi_randomizer_setup_pending), 'new-game decline stays off and prompt is consumed')
reset_save
Kernel.confirm_answer=true
SebiRandomizer.new_game_setup
assert(SebiRandomizer.active? && SebiRandomizer.state['starters'].length==3, 'new-game activation happens before starters')
SebiRandomizer.change('regions',[1])
reset_save
SebiRandomizer.change('enabled',true)
for gen in 1..9
  SebiRandomizer.change('regions',[gen])
  ids=SebiRandomizer.pool('wild').map(&:first)
  samples=80.times.map { pbGenerateWildPokemon(PBSpecies::PIKACHU,5).species }
  assert(!ids.empty? && samples.all? { |id| ids.include?(id) }, "generation #{gen} independent filter")
end
SebiRandomizer.change('regions',[1,2,3,4,5,6,7,8,9])
SebiRandomizer.change('shop_items',true)
shop=pbPokemonMart(Array.new(20,PBItems::POTION))
assert(shop.map(&:first).uniq.length>10, 'shop stock rerolls without changing caller list')
SebiRandomizer.change('gift',true)
gift=PokeBattle_Pokemon.new(PBSpecies::PIKACHU,27,$Trainer)
received=pbAddPokemon(gift)
assert(received.level==27, 'object gifts preserve their level across growth rates')
SebiRandomizer.change('wild_items',true)
item_rolls=100.times.map { pbGenerateWildPokemon(PBSpecies::PIKACHU,20).item }.select { |id| id>0 }
assert(item_rolls.uniq.length>10, 'wild held items use independent per-encounter rolls')
SebiRandomizer.change('trainer',false)
SebiRandomizer.change('trainer_items',true)
# Exercise held-item postprocessing with a real Pokemon that has an item.
rival=TrainerStub.new
opponent=PokeBattle_Pokemon.new(PBSpecies::PIKACHU,20,rival)
opponent.setItem(PBItems::POTION)
rolls=30.times.map do
  opponent.setItem(PBItems::POTION)
  SebiRandomizer.finish_trainer([rival,[],[opponent]],'trainer')[2][0].item
end
assert(rolls.uniq.length>10 && opponent.species==PBSpecies::PIKACHU, 'trainer held items independent from species')
SebiRandomizer.change('donation_legendary',false)
assert(!SebiSpecialActions.trade_species_allowed?(PBSpecies::MEWTWO), 'donations honor legend exclusion')
SebiRandomizer.change('custom_species',false)
assert(!SebiSpecialActions.trade_species_allowed?(PBSpecies::AURETOSK), 'donations honor custom exclusion')
SebiRandomizer.change('starter',false)
assert(!$game_switches[RandomizedChallenge::SWITCH], 'starter OFF routes intro to original regional choices')
$game_switches[247]=true
assert(SebiRandomizer.vanilla_starter(0)==PBSpecies::SPRIGATITO, 'vanilla starter fallback honors original selection')
legacy=PokemonGlobalMetadata.new
legacy.remove_instance_variable(:@sebi_randomizer)
$PokemonGlobal=legacy
$game_switches[RandomizedChallenge::SWITCH]=true
SebiRandomizer.manage
assert(SebiRandomizer.active?, 'adopting legacy random save preserves enabled state')
puts "PASS: #{$checks} offline integration assertions using real Pokemon Z data/scripts."
