require 'core_ext/deep_fetch'
require 'core_ext/stringify_keys'
require 'json_logic/truthy'
require 'json_logic/operation'
module JSONLogic
  def self.apply(logic, data)
    if logic.is_a?(Array)
      logic.map do |val|
        apply(val, data)
      end
    elsif !logic.is_a?(Hash)
      # Pass-thru
      logic
    else
      if data.is_a?(Hash)
        data = data.stringify_keys
      end
      data ||= {}

      operator, values = operator_and_values_from_logic(logic)
      Operation.perform(operator, values, data)
    end
  end

  def self.compile(logic)
    klass = Class.new { define_method(:to_s) { logic.to_s }  }

    case logic
    when Array

      klass.define_method(:evaluate) do |data|
        logic.map { |item| JSONLogic.compile(item) }.map { |item| item.evaluate(data) }
      end

    when Hash

      operation, values = logic.first
      values = [values] unless values.is_a?(Array)

      klass.define_method(:evaluate) do |data|
        compiled_values = values.map do |value|
          JSONLogic.compile(value)
        end

        evaluated_values =
          case operation
          when 'filter', 'some', 'none', 'all', 'map'
            input = compiled_values[0].evaluate(data)
            params = input&.map { |item| compiled_values[1].evaluate(item) }
            [input, params]
          when 'reduce'
            input = compiled_values[0].evaluate(data)
            accumulator = compiled_values[2].evaluate(data)
            [input, compiled_values[1], accumulator]
          else
            compiled_values.map { |item| item.evaluate(data) }
          end

        Operation.perform(operation, evaluated_values, data)
      end

    else

      klass.define_method(:evaluate) { |_data| logic }

    end

    klass.new
  end

  def self.apply(logic, data)
    compile(logic).evaluate(data)
  end

  # Return a list of the non-literal data used. Eg, if the logic contains a {'var' => 'bananas'} operation, the result of
  # uses_data on this logic will be a collection containing 'bananas'
  def self.uses_data(logic)
    collection = []

    if logic.kind_of?(Hash) || logic.kind_of?(Array) # If we are still dealing with logic, keep going. Else it's a value.
      operator, values = operator_and_values_from_logic(logic)

      if operator == 'var' # TODO: It may be that non-var operators use data so we may want a flag or collection that indicates data use.
        if values[0] != JSONLogic::ITERABLE_KEY
          collection << values[0]
        end
      else
        values.each do |val|
          collection.concat(uses_data(val))
        end
      end
    end

    return collection.uniq
  end

  def self.operator_and_values_from_logic(logic)
    # Unwrap single-key hash
    operator, values = logic.first

    # Ensure values is an array
    if !values.is_a?(Array)
      values = [values]
    end

    [operator, values]
  end

  def self.filter(logic, data)
    data.select { |d| apply(logic, d) }
  end

  def self.add_operation(operator, function)
    Operation.class.send(:define_method, operator) do |v, d|
      function.call(v, d)
    end
  end
end

require 'json_logic/version'
