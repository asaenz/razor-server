# -*- encoding: utf-8 -*-
class Razor::Validation::Attribute
  def initialize(name, checks)
    name.is_a?(String) or raise TypeError, "attribute name must be a string"
    name =~ /\A[-a-z0-9]+\z/ or raise ArgumentError, "attribute name is not valid"
    @name = name

    checks.is_a?(Hash) or raise TypeError, "must be followed by a hash"
    checks.each do |check, argument|
      respond_to?(check) or raise ArgumentError, "does not know how to perform a #{check} check"
      send(check, argument)
    end
  end

  def finalize(schema)
    Array(@exclude).each do |attr|
      schema.attribute(attr) or raise ArgumentError, "excluded attribute #{attr} by #{@name} is not defined in the schema"
    end

    Array(@also).each do |attr|
      schema.attribute(attr) or raise ArgumentError, "additionally required attribute #{attr} by #{@name} is not defined in the schema"
    end
  end

  def validate!(data)
    # if the key is not present, fail if required, otherwise we are done validating.
    unless data.has_key?(@name)
      @required and
        raise Razor::ValidationFailure, _("required attribute %{name} is missing") % {name: @name}
      return true
    end

    @exclude and @exclude.each do |what|
      data.has_key?(what) and
        raise Razor::ValidationFailure, _("if %{name} is present, %{exclude} must not be present") % {name: @name, exclude: what}

    @also and @also.each do |what|
        data.has_key?(what) or
          raise Razor::ValidationFailure, _("if %{name} is present, %{also} must also be present") % {name: @name, also: @also.join(', ')}
      end
    end

    value = data[@name]

    if @type
      Array(@type).any? do |check|
        # If we don't match the base type, go to the next one; if none match our
        # final validation failure will trigger and raise.
        next false unless value.class <= check[:type]

        # If there is a validation
        begin
          check[:validate] and check[:validate].call(value)
        rescue => e
          raise Razor::ValidationFailure, _("attribute %{name} fails type checking for %{type}: %{error}") % {name: @name, type: ruby_type_to_json(check[:type]), error: e.to_s}
        end

        # If we got here we passed all the checks, and have a match, so we are good.
        break true
      end or raise Razor::ValidationFailure, n_(
        "attribute %{name} has wrong type %{actual} where %{expected} was expected",
        "attribute %{name} has wrong type %{actual} where one of %{expected} was expected",
        Array(@type).count) % {
        name:     @name,
        actual:   ruby_type_to_json(value),
        expected: Array(@type).map {|x| ruby_type_to_json(x[:type]) }.join(', ')}
    end

    if @references
      @references[@refname => value] or
        raise Razor::ValidationFailure.new(_("attribute %{name} must refer to an existing instance") % {name: @name}, 404)
    end

    if @one_of
      @one_of.any? {|match| value == match } or
        raise Razor::ValidationFailure, _("attribute %{name} must refer to one of %{valid}") % {name: @name, valid: @one_of.map {|x| x.nil? ? 'null' : x }.join(', ')}
    end

    return true
  end

  def required(is)
    @required = !!is
  end

  def type(which)
    which = Array(which)
    which.all? {|x| x.nil? or x.is_a?(Module) } and not which.empty? or
      raise ArgumentError, "type checks must be passed a class, module, nil, or an array of the same"

    @type = which.map do |entry|
      if    entry.nil?   then {type: NilClass}
      elsif entry <= URI then {type: String, validate: -> str { URI.parse(str) }}
      else                    {type: entry}
      end
    end
  end

  def exclude(what)
    unless what.is_a?(String) or (what.is_a?(Array) and what.all?{|x| x.is_a?(String)})
      raise ArgumentError, "attribute exclusions must be a string, or an array of strings"
    end

    @exclude = Array(what)
  end

  def also(what)
    unless what.is_a?(String) or (what.is_a?(Array) and what.all?{|x| x.is_a?(String)})
      raise ArgumentError, "additional attribute requirements must be a string, or an array of strings"
    end

    @also = Array(what)
  end

  def references(what)
    what.is_a?(Class) and what <= Sequel::Model or
      raise ArgumentError, "attribute references must be a Sequel::Model class"
    @references = what
    @refname    = @name.to_sym
  end

  ValidTypesForOneOf = [String, Numeric, TrueClass, FalseClass, NilClass]
  ValidTypesForOneOfJSON = ValidTypesForOneOf.map {|x| ruby_type_to_json(x) }.join(', ')
  def one_of(what)
    what.is_a? Array or
      raise ArgumentError, "one_of takes an array of options, not a #{ruby_type_to_json(what)}"
    what.each do |value|
      ValidTypesForOneOf.any? {|x| value.is_a? x } or
        raise ArgumentError, "one_of values must be one of #{ValidTypesForOneOfJSON}, not #{ruby_type_to_json(value)}"
    end

    what.uniq == what or raise ArgumentError, "one_of contains duplicate values"

    @one_of = what
  end
end
