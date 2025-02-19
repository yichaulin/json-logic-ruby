module JSONLogic
  ITERABLE_KEY = "".freeze

  class Operation
    LAMBDAS = {
      'var' => ->(v, d) do
        if v.empty?
          d
        elsif v == [JSONLogic::ITERABLE_KEY]
          if d.is_a?(Hash)
            d[JSONLogic::ITERABLE_KEY]
          else
            d
          end
        else
          keys = VarCache.fetch_or_store(v[0])
          d.deep_fetch(keys, v[1])
        end
      end,
      'missing' => ->(v, d) do
        v.flatten.select do |val|
          keys = VarCache.fetch_or_store(val)
          d.deep_fetch(keys).nil?
        end
      end,
      'missing_some' => ->(v, d) {
        present = v[1] & d.keys
        present.size >= v[0] ? [] : LAMBDAS['missing'].call(v[1], d)
      },
      'some' => -> (v,d) do
        return false unless v[0].is_a?(Array)

        v[1].any? do |item|
          item.truthy?
        end
      end,
      'filter' => -> (v,d) do
        return [] unless v[0].is_a?(Array)

        v[0].select.with_index do |_, index|
          v[1][index].truthy?
        end
      end,
      'substr' => -> (v,d) do
        limit = -1
        if v[2]
          if v[2] < 0
            limit = v[2] - 1
          else
            limit = v[1] + v[2] - 1
          end
        end

         v[0][v[1]..limit]
      end,
      'none' => -> (v,d) do
        return false unless v[0].is_a?(Array)

        v[1].all? do |item|
          item.falsy?
        end
      end,
      'all' => -> (v,d) do
        return false unless v[0].is_a?(Array)
        # Difference between Ruby and JSONLogic spec ruby all? with empty array is true
        return false if v[0].empty?

        v[1].all? do |item|
          item.truthy?
        end
      end,
      'reduce' => -> (v,d) do
        return v[2] unless v[0].is_a?(Array)
        v[0].inject(v[2]) { |acc, val| v[1].evaluate({ "current" => val, "accumulator" => acc })}
      end,
      'map' => -> (v,d) do
        return [] unless v[0].is_a?(Array)
        v[1]
      end,
      'if' => ->(v, d) {
        v.each_slice(2) do |condition, value|
          return condition if value.nil?
          return value if condition.truthy?
        end

        nil
      },
      '=='    => ->(v, d) { v[0].to_s == v[1].to_s },
      '==='   => ->(v, d) { v[0] == v[1] },
      '!='    => ->(v, d) { v[0].to_s != v[1].to_s },
      '!=='   => ->(v, d) { v[0] != v[1] },
      '!'     => ->(v, d) { v[0].falsy? },
      '!!'    => ->(v, d) { v[0].truthy? },
      'or'    => ->(v, d) { v.find(&:truthy?) || v.last },
      'and'   => ->(v, d) {
        result = v.find(&:falsy?)
        result.nil? ? v.last : result
      },
      '?:'    => ->(v, d) { LAMBDAS['if'].call(v, d) },
      '>'     => ->(v, d) { v.map(&:to_f).each_cons(2).all? { |i, j| i > j } },
      '>='    => ->(v, d) { v.map(&:to_f).each_cons(2).all? { |i, j| i >= j } },
      '<'     => ->(v, d) { v.map(&:to_f).each_cons(2).all? { |i, j| i < j } },
      '<='    => ->(v, d) { v.map(&:to_f).each_cons(2).all? { |i, j| i <= j } },
      'max'   => ->(v, d) { v.map(&:to_f).max },
      'min'   => ->(v, d) { v.map(&:to_f).min },
      '+'     => ->(v, d) { v.map(&:to_f).reduce(:+) },
      '-'     => ->(v, d) { v.map!(&:to_f); v.size == 1 ? -v.first : v.reduce(:-) },
      '*'     => ->(v, d) { v.map(&:to_f).reduce(:*) },
      '/'     => ->(v, d) { v.map(&:to_f).reduce(:/) },
      '%'     => ->(v, d) { v.map(&:to_i).reduce(:%) },
      '^'     => ->(v, d) { v.map(&:to_f).reduce(:**) },
      'merge' => ->(v, d) { v.flatten },
      'in'    => ->(v, d) { v[1].include?(v[0]) },
      'cat'   => ->(v, d) { v.map(&:to_s).join },
      'log'   => ->(v, d) { puts v }
    }

    def self.perform(operator, values, data)
      if is_standard?(operator)
        LAMBDAS[operator.to_s].call(values, data)
      else
        send(operator, values, data)
      end
    end

    def self.is_standard?(operator)
      LAMBDAS.key?(operator.to_s)
    end

    def self.add_operation(operator, function)
      self.class.send(:define_method, operator) do |v, d|
        function.call(v, d)
      end
    end
  end
end
