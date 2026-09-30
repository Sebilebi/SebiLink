# Offline catalog builder. CSV source: PokeAPI pokemon_species.csv (see README).
require 'csv'
require 'digest'
game = File.expand_path('../..', __dir__)
csv_path = ARGV.fetch(0)
official = {}
CSV.foreach(csv_path, :headers => true) do |row|
  key = row['identifier'].upcase.gsub(/[^A-Z0-9]/, '')
  official[key] = [row['generation_id'].to_i, row['is_legendary'].to_i, row['is_mythical'].to_i]
end
official['NIDORANFE'] = official['NIDORANF']
official['NIDORANMA'] = official['NIDORANM']
records = {}
File.read(File.join(game, 'PBS/pokemon.txt'), :encoding => 'UTF-8').split(/(?=^\[\d+\])/).each do |block|
  next unless block =~ /^\[(\d+)\]/
  id = $1.to_i
  fields = block.lines.map { |l| l.strip.split('=', 2) }.select { |p| p.length == 2 }.to_h
  records[id] = fields
end
by_name = records.to_h { |id, r| [r['InternalName'], id] }
parents = {}
records.each do |id, r|
  (r['Evolutions'] || '').split(',').each_slice(3) do |name, _, _|
    target = by_name[name]
    (parents[target] ||= []) << id if target && target != id
  end
end
region = lambda do |id, seen = []|
  r = records.fetch(id)
  key = r['InternalName'].upcase
  next official[key][0] if official[key]
  next 6 if seen.include?(id) || !parents[id] || parents[id].empty?
  region.call(parents[id].first, seen + [id])
end
stage = lambda do |id, seen = []|
  next 0 if seen.include?(id) || !parents[id] || parents[id].empty?
  [2, 1 + parents[id].map { |p| stage.call(p, seen + [id]) }.min].min
end
# Explicitly audited forms from the CURRENT Scripts.rxdata MultipleForms registry.
# r = official regional, c = custom Z, o = other official, each with origin generation.
forms = {}
{7 => %w[RAICHU SANDSLASH NINETALES GOLEM MUK EXEGGUTOR MAROWAK PERSIAN RATICATE],
 8 => %w[RAPIDASH MRMIME STUNFISK SLOWKING SLOWBRO WEEZING ARTICUNO ZAPDOS MOLTRES TYPHLOSION AVALUGG DECIDUEYE SAMUROTT GOODRA ARCANINE ELECTRODE VOLTORB LILLIGANT BRAVIARY ZOROARK],
 9 => %w[TAUROS]}.each { |gen, names| names.each { |name| forms[name] = [[1, gen, 'r']] } }
%w[DUGTRIO DONPHAN DELIBIRD MAGNEZONE VOLCARONA HARIYAMA TENTACRUEL DARMANITAN LUGIA UMBREON PIKACHU].each do |name|
  forms[name] = [[1, 6, 'c']]
end
{'DEOXYS'=>[1,2,3], 'SHAYMIN'=>[1], 'TORNADUS'=>[1], 'THUNDURUS'=>[1], 'LANDORUS'=>[1],
 'KYUREM'=>[1,2], 'MELOETTA'=>[1], 'MEOWSTIC'=>[1], 'AEGISLASH'=>[1]}.each do |name, ids|
  gen = official.fetch(name)[0]
  forms[name] = ids.map { |form| [form, gen, 'o'] }
end
forms['BASCULIN'] = [[1,5,'o'], [2,8,'r']]
out = ["# SebiLink species catalog v1. id|internalName|generation|kind|stage|form:generation:kind,...",
       "# PokeAPI CSV SHA256: #{Digest::SHA256.file(csv_path).hexdigest}",
       '# kind: n normal, l legendary, m mythical, c custom Z; forms: o official, r regional, c custom.']
records.sort.each do |id, r|
  name = r.fetch('InternalName')
  next if name == 'MISSINGNO'
  data = official[name.upcase]
  kind = data ? (data[1] == 1 ? 'l' : data[2] == 1 ? 'm' : 'n') : 'c'
  alternates = (forms[name] || []).map { |f| f.join(':') }.join(',')
  out << [id, name, region.call(id), kind, stage.call(id), alternates].join('|')
end
File.write(File.join(game, 'multiplayer/randomizer-species.txt'), out.join("\n") + "\n")
puts "Catalog: #{records.length - 1} species, #{forms.length} species with audited forms."
