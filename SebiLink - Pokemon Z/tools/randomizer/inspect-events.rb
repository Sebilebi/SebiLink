# Read-only event inspection, without starting RGSS/the game.
class Table
  def self._load(data); new; end
end
class Tone
  def self._load(data); new; end
end
class Color
  def self._load(data); new; end
end
module RPG
  class Map; end
  class AudioFile; end
  class EventCommand; end
  class MoveCommand; end
  class MoveRoute; end
  class Event
    class Page
      class Condition; end
      class Graphic; end
    end
  end
end
game = File.expand_path('../..', __dir__)
ARGV.each do |arg|
  map = Marshal.load(File.binread(File.join(game, 'Data', format('Map%03d.rxdata', arg.to_i))))
  map.instance_variable_get(:@events).each_value do |event|
    event.instance_variable_get(:@pages).each_with_index do |page, index|
      commands = page.instance_variable_get(:@list)
      scripts = commands.select { |c| [355,655].include?(c.instance_variable_get(:@code)) }
      next unless scripts.any? { |c| c.instance_variable_get(:@parameters).join =~ /starter|pbAddPokemon|enable_random/ }
      puts "Map #{arg}, event #{event.instance_variable_get(:@id)}, page #{index}, #{page.instance_variable_get(:@condition).instance_variables.map { |v| [v,page.instance_variable_get(:@condition).instance_variable_get(v)] }.inspect}"
      scripts.each { |c| puts c.instance_variable_get(:@parameters) }
    end
  end
end
