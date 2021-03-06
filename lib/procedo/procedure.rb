# -*- coding: utf-8 -*-
module Procedo

  FORMULA_TRUC = {
    shape: ["whole#net_surface_area"]
  }


  # This class represents a procedure
  class Procedure

    attr_reader :id, :short_name, :namespace, :operations, :natures, :parent, :position, :variables, :variable_names, :version

    def initialize(element, options = {})
      short_name = element.attr("name").to_s.split(NAMESPACE_SEPARATOR)
      if short_name.size == 2
        @namespace = short_name.shift.to_sym
      elsif short_name.size != 1
        raise ArgumentError, "Bad name of procedure: #{element.attr("name").to_s.inspect}"
      end
      @namespace = DEFAULT_NAMESPACE if @namespace.blank?
      @short_name = short_name.shift.to_s.to_sym
      @required = (element.attr('required').to_s == "true" ? true : false)
      @parent = options[:parent] if options[:parent]
      @position = options[:position] || 0

      @system = !!(element.attr('system') == "true")

      # Check version
      @version = element.attr("version").to_s
      unless @version =~ /\A\d+\z/
        raise Procedo::Errors::MissingAttribute, "Valid attribute 'version' must be given for the procedure #{not_so_short_name}"
      end
      @version = @version.to_i

      # Collect procedure natures
      @natures = element.attr('natures').to_s.strip.split(/[\s\,]+/).compact.map(&:to_sym)

      # Check roles with procedure natures
      roles  = []
      for nature in @natures
        unless item = Nomen::ProcedureNatures[nature]
          raise Procedo::Errors::UnknownProcedureNature, "Procedure nature #{nature} is unknown for #{self.name}."
        end
        # List all roles
        roles += item.roles.collect{|role| "#{nature}-#{role}"}
      end
      roles.uniq!

      # Load variable_names
      @variable_names = []
      for item in element.xpath("xmlns:variables/xmlns:variable")
        @variable_names << item.attr("name").to_sym
      end

      # Load and check variables
      given_roles, position = [], 1
      @variables = element.xpath("xmlns:variables/xmlns:variable").inject(HashWithIndifferentAccess.new) do |hash, variable|
        v = Variable.new(self, variable, position)
        position += 1
        for role in v.roles
          if roles.include?(role)
            given_roles << role
          else
            raise Procedo::Errors::UnknownRole, "Role #{role} is ungiveable in procedure #{self.name}"
          end
        end
        hash[variable.attr("name").to_s] = v
        hash
      end

      # Check ungiven roles
      remaining_roles = roles - given_roles.uniq
      if remaining_roles.any?
        raise Procedo::Errors::MissingRole, "Remaining roles of procedure #{self.name} are not given: #{remaining_roles.join(', ')}"
      end

      # Check producers
      for variable in new_variables
        unless variable.producer.is_a?(Variable)
          raise  Procedo::Errors::UnknownAspect, "Unknown variable producer for #{variable.name}"
        end
      end

      # Load operations
      @operations = element.xpath("xmlns:operations/xmlns:operation").inject({}) do |hash, operation|
        hash[operation.attr("id").to_s] = Operation.new(self, operation)
        hash
      end
      unless @operations.keys.size == element.xpath("xmlns:operations/xmlns:operation").size
        raise Procedo::Errors::NotUniqueIdentifier.new("Each operation must have a unique identifier (#{self.name})")
      end

      # Compile it
      self.compile!
    end

    def self.of_nature(nature)
      Procedo.procedures_of_nature(nature)
    end

    # Returns true if the procedure nature match one of the given natures
    def of_nature?(*natures)
      (self.natures & natures).any?
    end

    def of_activity_family?(*families)
      (self.activity_families & families).any?
    end

    # Returns activity families of the procedure
    def activity_families
      @activity_families ||= self.natures.map do |n|
        Nomen::ProcedureNatures[n].activity_families.map do |f|
          Nomen::ActivityFamilies.all(f)
        end
      end.flatten.uniq.map(&:to_sym)
    end


    def not_so_short_name
      namespace.to_s + NAMESPACE_SEPARATOR + short_name.to_s
    end

    def name
      not_so_short_name + VERSION_SEPARATOR + self.version.to_s
    end
    alias :uid :name

    def flat_version
      "v" + self.version.to_s.gsub(/\W/, '_')
    end

    def need_parameters?
      return self.operations.values.detect(&:need_parameters?)
    end

    # Returns if the procedure is system
    def system?
      @system
    end

    # Returns if the procedure is required
    def required?
      @required
    end

    # Returns human_name of the procedure
    def human_name
      default = []
      default << "procedures.#{short_name}".to_sym
      default << "labels.procedures.#{not_so_short_name}".to_sym
      default << "labels.procedures.#{short_name}".to_sym
      default << "labels.#{short_name}".to_sym
      default << short_name.to_s.humanize
      return "procedures.#{not_so_short_name}".t(default: default)
    end

    # Returns the fixed time for a procedure
    def minimal_duration
      return self.operations.values.map(&:duration).compact.sum
    end
    alias :fixed_duration :minimal_duration

    # Returns the spread duration for operation with unknown duration
    def spread_time(duration)
      return (duration - self.fixed_duration).to_d / self.operations.values.select(&:no_duration?).count
    end

    # Returns only variables which must be built during runnning process
    def new_variables
      @variables.values.select(&:new?)
    end

    def handled_variables
      @variables.values.select(&:handled?)
    end


    def cast_expr(expr, datatype = :string)
      if datatype == :integer
        "#{expr}.to_i"
      elsif datatype == :decimal
        "#{expr}.to_f"
      elsif datatype == :choice
        "#{expr}.to_sym"
      elsif datatype == :measure # No unit expected for now
        "#{expr}.to_f"
      elsif datatype == :boolean
        "['t', 'true', '1'].include?(#{expr}.to_s)"
      elsif datatype == :point or datatype == :geometry
        "(#{expr}.blank? ? Charta::Geometry.empty : Charta::Geometry.new(#{expr}, :WGS84))"
      else
        "#{expr}.to_s"
      end
    end

    # Compile a procedure to manage interventions
    def compile!
      rubyist = Procedo::Compilers::Rubyist.new
      full_name = ["::Procedo", "CompiledProcedures", self.namespace.to_s.camelcase, self.short_name.to_s.camelcase, "V#{self.version}"]
      code = "class #{full_name.last} < ::Procedo::CompiledProcedure\n\n"

      for variable in @variables.values
        code << "  class #{variable.name.to_s.camelcase} < ::Procedo::CompiledVariable\n\n"

        code << "    def initialize(procedure, attributes = {})\n"
        code << "      super(procedure)\n"
        if variable.new?
          code << "      @variant = (attributes[:variant].present? ? ProductNatureVariant.find(attributes[:variant]) : nil)\n"
        else
          code << "      @actor = (attributes[:actor].blank? ? nil : Product.find(attributes[:actor]))\n"
        end
        for destination in variable.destinations
          code << "      @destinations[:#{destination}] = " + cast_expr("attributes[:destinations][:#{destination}]", Nomen::Indicators[destination].datatype) + "\n"
        end
        for handler in variable.handlers
          code << "      if attributes[:handlers][:#{handler.name}].is_a? Hash\n"
          code << "        @handlers[:#{handler.name}] = " + cast_expr("attributes[:handlers][:#{handler.name}][:value]", handler.indicator.datatype) + "\n"
          code << "      end\n"
        end
        code << "    end\n\n"

        code << "    def present?\n"
        code << "      @#{variable.new? ? 'variant' : 'actor'}.is_a?(Ekylibre::Record::Base)\n"
        code << "    end\n\n"

        code << "    def has_indicator?(indicator)\n"
        code << "      present? and @#{variable.new? ? 'variant' : 'actor'}.has_indicator?(indicator)\n"
        code << "    end\n\n"

        # Method to get indicator values on @actor/@variant
        code << "    def get(indicator, options = {})\n"
        if variable.destinations.include?(:shape)
          code << "      if !@destinations[:shape].empty? and indicator == :net_surface_area and !options[:individual]\n"
          code << "        value = @destinations[:shape].area\n"
          if variable.new?
            code << "      elsif @variant\n"
            code << "        value = @variant.get(indicator)\n"
          else
            code << "      elsif @actor\n"
            code << "        value = @actor.get(indicator, at: now, gathering: !options[:individual])\n"
          end
          code << "      else\n"
          code << "        raise Procedo::Errors::UnavailableReading, \"No way to access \#{'individual ' if options[:individual]}readings for #{variable.name}#\#{indicator.inspect}\"\n"
          code << "      end\n"
        else
          code << "      unless #{variable.new? ? '@variant' : '@actor'}\n"
          code << "        raise Procedo::Errors::UnavailableReading, \"No way to access \#{'individual ' if options[:individual]}readings for #{variable.name}#\#{indicator.inspect}\"\n"
          code << "      end\n"
          if variable.new?
            code << "      value = @variant.get(indicator)\n"
          else
            code << "      value = @actor.get(indicator, at: now, gathering: !options[:individual])\n"
          end
        end
        code << "      unless value\n"
        code << "        raise Procedo::Errors::UnavailableReading, \"Nil \#{'individual ' if options[:individual]}reading given #{variable.name}#\#{indicator.inspect}\"\n"
        code << "      end\n"
        code << "      datatype = Nomen::Indicators[indicator].datatype\n"
        code << "      return (datatype == :decimal ? value.to_s.to_f : value)\n"
        code << "    end\n\n"

        rubyist.self_value = "self"

        # Destinations
        for destination in variable.destinations
          code << "    def impact_destination_#{destination}!\n"
          # Updates handlers through backward formula
          for converter in variable.backward_converters_from(destination)
            rubyist.value = "@destinations[:#{destination}]"
            rubyist.compile(converter.backward_tree)
            code << "      begin\n"
            code << "        value = #{rubyist.compiled}\n"
            code << "        if value != @handlers[:#{converter.handler.name}]\n"
            code << "          @handlers[:#{converter.handler.name}] = value\n"
            code << "          impact_handler_#{converter.handler.name}!\n"
            code << "        end\n"
            code << "      rescue Procedo::Errors::UncomputableFormula => e\n"
            code << "        Rails.logger.error e.message\n"
            code << "      end\n"
          end
          # Impacts on handlers of other variables that uses "our" destination
          for other in variable.others
            for handler in other.handlers
              if handler.forward_depend_on?(variable.name)
                code << "      # Updates #{handler.name} of #{other.name} if possible\n"
                code << "      procedure.#{other.name}.impact_handler_#{handler.name}!\n"
              end
            end
          end

          code << "    end\n\n"
        end

        # Handlers
        for h in variable.handlers
          rubyist.value = "@handlers[:#{h.name}]"
          # Method to check is handler is usable
          code << "    def can_use_#{h.name}?\n"
          if h.check_usability?
            rubyist.compile(h.usability_tree)
            code << "      #{rubyist.compiled}\n"
            # code << "    rescue\n"
            # code << "      return false\n"
          else
            code << "      return true\n"
          end
          code << "    end\n\n"

          # Method to impact handler's new value
          code << "    def impact_handler_#{h.name}!\n"
          if h.check_usability?
            code << "      return unless can_use_#{h.name}?\n"
          end
          for converter in h.forward_converters
            rubyist.compile(converter.forward_tree)
            code << "      begin\n"
            code << "        value = #{rubyist.compiled}\n"
            code << "        if value != @destinations[:#{converter.destination}]\n"
            code << "          @destinations[:#{converter.destination}] = value\n"
            code << "          impact_destination_#{converter.destination}!\n"
            code << "        end\n"
            code << "      rescue Procedo::Errors::UncomputableFormula => e\n"
            code << "        Rails.logger.error e.message\n"
            code << "      end\n"
          end
          code << "    end\n\n"
        end

        # Actor or Variant
        code << "    def impact_#{variable.new? ? :variant : :actor}!\n"
        if variable.others.detect{|other| other.parted? and other.producer == variable }
          variant      = (variable.new? ? "@variant" : "@actor.variant")
          variant_test = (variable.new? ? variant : "@actor and #{variant}")
          code << "      if #{variant_test}\n"

          # Set variants of "parted-from variables"
          for other in variable.others
            if other.parted? and other.producer == variable
              code << "        # Updates variant of #{other.name} if possible\n"
              code << "        if procedure.#{other.name}.variant != #{variant}\n"
              code << "          procedure.#{other.name}.variant = #{variant}\n"
              code << "          procedure.#{other.name}.impact_#{other.new? ? :variant : :actor}!\n"
              code << "        end\n"
            end
          end
          code << "      end\n"
        end

        # Sets default destinations
        for other in variable.others
          ref = other.name
          for destination in other.destinations
            if other.default(destination) =~ /\A\:\s*#{variable.name}\s*\z/
              code << "      # Updates default #{destination} of #{ref} if possible\n"
              dest = "procedure.#{ref}.destinations[:#{destination}]"
              code << "      if #{dest}.blank? or procedure.updater?(:casting, :#{variable.name})"
              code << " or procedure.updater?(:global, :support)" if [:storage, :variant_localized_in_storage].include?(variable.default_actor)
              code << "\n"

              code << "        begin\n"
              code << "          #{dest} = "
              code << "@destinations[:#{destination}] || " if variable.destinations.include?(destination)
              code << "self.get(:#{destination}, at: now)\n"
              if [:geometry, :point].include?(Nomen::Indicators[destination].datatype)
                code << "          #{dest} = (#{dest}.blank? ? Charta::Geometry.empty : Charta::Geometry.new(#{dest}))\n"
              end
              code << "          procedure.#{ref}.impact_destination_#{destination}!\n"
              code << "        rescue Procedo::Errors::UncomputableFormula => e\n"
              code << "          Rails.logger.error e.message\n"
              code << "        end\n"
              code << "      end\n"
            end
          end
        end

        unless variable.new?
          for destination in variable.destinations
            dest = "@destinations[:#{destination}]"
            code << "        begin\n"
            code << "          #{dest} = self.get(:#{destination}, at: now)\n"
            if [:geometry, :point].include?(Nomen::Indicators[destination].datatype)
              code << "          #{dest} = (#{dest}.blank? ? Charta::Geometry.empty : Charta::Geometry.new(#{dest}))\n"
            end
            code << "          impact_destination_#{destination}!\n"
            code << "        rescue Procedo::Errors::UncomputableFormula => e\n"
            code << "          Rails.logger.error e.message\n"
            code << "        end\n"
          end
        end

        # Refresh depending handlers
        for handler in variable.handlers
          if handler.forward_depend_on?(:self)
            code << "      # Updates #{handler.name} of self if possible\n"
            code << "      impact_handler_#{handler.name}!\n"
          elsif handler.backward_depend_on?(:self)
            for converter in handler.converters.select{|c| c.backward_depend_on?(:self) }
              code << "      # Updates #{converter.destination} of self if possible\n"
              code << "      impact_destination_#{converter.destination}!\n"
            end
          end
        end

        for other in variable.others
          for handler in other.handlers
            if handler.forward_depend_on?(variable.name)
              code << "      # Updates #{handler.name} of #{other.name} if possible\n"
              code << "      procedure.#{other.name}.impact_handler_#{handler.name}!\n"
            elsif handler.backward_depend_on?(variable.name)
              for converter in handler.converters.select{|c| c.backward_depend_on?(variable.name) }
                code << "      # Updates #{converter.destination} of self if possible\n"
                code << "      impact_destination_#{converter.destination}!\n"
              end
            end
          end
        end

        code << "    end\n\n"

        code << "  end\n\n"
      end

      code << "  attr_reader " + @variables.keys.collect{|v| ":#{v}" }.join(', ') + "\n\n"

      code << "  def initialize(casting, global, updater)\n"
      max = @variables.keys.map(&:size).max
      for variable in @variables.keys
        code << "    @#{variable.ljust(max)} = #{variable.camelcase}.new(self, casting[:#{variable}])\n"
      end
      code << "    @__support__ = ProductionSupport.find_by(id: global[:support])\n"
      code << "    @__now__     = global[:at].blank? ? Time.now : global[:at].to_time\n"
      code << "    @__updater__ = updater.split(':').map(&:to_sym)\n"
      code << "  end\n\n"


      code << "  def impact!\n"
      code << "    if @__updater__.first == :global\n"
      code << "      if @__updater__.second == :support\n"
      for variable in self.variables.values
        if variable.new?
          if variable.default_variant == :production
            code << "        #{variable.name}.variant = @__support__.production_variant\n"
            code << "        #{variable.name}.impact_variant!\n"
          end
        else
          if variable.default_actor == :storage
            code << "        #{variable.name}.actor = @__support__.storage\n"
            code << "        #{variable.name}.impact_actor!\n"
          elsif variable.default_actor == :default_storage_of_support
            code << "        #{variable.name}.actor = @__support__.storage.default_storage\n"
            code << "        #{variable.name}.impact_actor!\n"
          elsif variable.default_actor == :variant_localized_in_storage
            code << "        __localizeds__ = @__support__.storage.localized_variants(@__support__.production_variant, at: now!)\n"
            code << "        if __localizeds__.any?\n"
            code << "          #{variable.name}.actor = __localizeds__.first\n"
            code << "          #{variable.name}.impact_actor!\n"
            code << "        end\n"
          elsif variable.default_actor.to_s =~ /\Afirst_localized_in\:/
            unless v = self.variables[variable.default_actor.to_s.split(":").second.strip]
              raise Procedo::Errors::UnknownVariable, "Unknown variable used in #{variable.default_actor}"
            end
            code << "        if #{v.name}.actor and #{v.name}.actor.containeds(now!).any?\n"
            code << "          #{variable.name}.actor = #{v.name}.actor.containeds.first\n"
            code << "          #{variable.name}.impact_actor!\n"
            code << "        end\n"
          elsif variable.default_actor != :none
            raise Procedo::Errors::InvalidExpression, "Invalid default-actor expression: #{variable.default_actor.inspect}"
          end
        end
      end
      # global:at is called at every interventions form call so we use it
      # TODO replace this in a cleaner way with a global updater like "global:start"
      code << "      elsif @__updater__.second == :at\n"
      # What to do ? Check existence and destinations of products at this moment ?
      for variable in self.variables.values
        for destination in variable.destinations
          code << "        #{variable.name}.impact_destination_#{destination}!\n"
        end
      end
      code << "      end\n"
      code << "    elsif @__updater__.first == :casting\n"
      code << self.variables.values.collect do |variable|
        vcode  = "if @__updater__.second == :#{variable.name}\n"
        vcode << "  if @__updater__.third == :#{variable.new? ? :variant : :actor}\n"
        vcode << "    #{variable.name}.impact_#{variable.new? ? :variant : :actor}!\n"
        if variable.handlers.any?
          vcode << "  elsif @__updater__.third == :handlers\n"
          vcode << variable.handlers.collect do |handler|
            hcode  = "if @__updater__.fourth == :#{handler.name}\n"
            hcode << "  #{variable.name}.impact_handler_#{handler.name}!\n"
          end.join("els").dig(2)
          vcode << "    else\n"
          vcode << "      raise Procedo::Errors::UnknownHandler, \"Unknown handler \#{@__updater__.fourth} for #{variable.name}\"\n"
          vcode << "    end\n"
        end
        vcode << "  else\n"
        vcode << "    raise Procedo::Errors::UnknownAspect, \"Unknown aspect \#{@__updater__.third} for #{variable.name}\"\n"
        vcode << "  end\n"
      end.join("els").dig(3)
      code << "      else\n"
      code << "        raise Procedo::Errors::UnknownVariable, \"Unknown variable \#{@__updater__.second}\"\n"
      code << "      end\n"
      code << "    elsif @__updater__.first == :initial\n"
      # Refresh all handlers from all destinations
      for variable in self.variables.values
        if variable.handlers.any?
          for destination in variable.destinations
            code << "      #{variable.name}.impact_destination_#{destination}!\n"
          end
        end
      end
      code << "    else\n"
      code << "      raise Procedo::Errors::UnknownAspect, \"Unknown part \#{@__updater__.first}\"\n"
      code << "    end\n"
      code << "  end\n\n"

      code << "  def casting\n"
      code << "    { " + @variables.values.collect do |variable|
        vcode = "#{variable.name}: "
        if variable.new?
          vcode << "{variant: @#{variable.name}.variant_id"
        else
          vcode << "{actor: @#{variable.name}.actor_id"
        end
        if variable.handlers.any?
          vcode << ", destinations: {"
          vcode << variable.destinations.collect do |destination|
            indicator = Nomen::Indicators[destination]
            if [:geometry, :point].include?(indicator.datatype)
              "#{destination}: @#{variable.name}.destinations[:#{destination}].to_geojson"
            else
              "#{destination}: @#{variable.name}.destinations[:#{destination}]"
            end
          end.join(', ')
          vcode << "}, handlers: {"
          vcode << variable.handlers.collect do |handler|
            indicator = handler.indicator
            hcode = "#{handler.name}: {value: "
            if [:measure, :decimal].include?(indicator.datatype)
              hcode << "@#{variable.name}.handlers[:#{handler.name}].round(3).to_f"
            elsif [:geometry, :point].include?(indicator.datatype)
              hcode << "@#{variable.name}.handlers[:#{handler.name}].to_geojson"
            elsif indicator.datatype == :integer
              hcode << "@#{variable.name}.handlers[:#{handler.name}].to_i"
            else
              hcode << "@#{variable.name}.handlers[:#{handler.name}]"
            end
            hcode << ", usable: @#{variable.name}.can_use_#{handler.name}?"
            hcode << "}"
            hcode
          end.join(', ')
          vcode << "}"
        end
        vcode << "}"
        vcode
      end.join(",\n").dig(3).strip + "\n"
      code << "    }\n"
      code << "  end\n\n"

      code << "end\n"

      for mod in full_name[0..-2].reverse
        code = "module #{mod}\n" + code.dig + "end"
      end

      if Rails.env.development?
        file = Rails.root.join("tmp", "code", "compiled_procedures", "#{self.name}.rb")
        FileUtils.mkdir_p(file.dirname)
        File.write(file, code)
      end

      class_eval(code, "(procedure #{self.name})")
      Procedo::CompiledProcedure[self.name] = full_name.join("::").constantize
    end

    # Computes what have to be updated if the given value in
    # the casting is considered to be updated
    # Returns a hash with the list of updates
    def impact(casting, global, updater)
      proc = Procedo::CompiledProcedure[self.name].new(casting, global, updater)
      before = proc.casting
      proc.impact!
      after = proc.casting
      return after
    end

    # generates a hash associating one actor (as the hash value) to each procedure variable (as the hash key) whenever possible
    # ==== Parameters:
    #         - actors, a list of actors possibly matching procedure variables
    def matching_variables_for(*actors)
      actors.flatten!
      result = {}
      # generating arrays of actors matching each variable
      # and variables matching each actor
      actors_for_each_variable = Hash.new
      @variables.values.each do |variable|
        actors_for_each_variable[variable] = variable.possible_matching_for(actors)
      end

      variables_for_each_actor = actors_for_each_variable.inject({}) do |res, (variable, actors_ary)|
        unless actors_ary.blank?
          actors_ary.each do |actor|
            res[actor] ||= []
            res[actor] << variable
          end
        end
        res
      end

      # cleaning variables with no actor
      actors_for_each_variable.each do |variable, actors_ary|
        if actors_ary.empty?
          result[variable] = nil
          actors_for_each_variable.delete(variable)
        end
      end

      # setting cursors
      current_variable = current_actor = 0

      while actors_for_each_variable.values.flatten.compact.present?
        # first, manage all variables having only one actor matching
        while current_variable < actors_for_each_variable.length
          current_variable_key = actors_for_each_variable.keys[current_variable]
          if actors_for_each_variable[current_variable_key].count == 1 && actors_for_each_variable[current_variable_key].present? # only one actor for the current variable
            result[current_variable_key] = actors_for_each_variable[current_variable_key].first
            clean(variables_for_each_actor, actors_for_each_variable, result[current_variable_key], current_variable_key)
            # restart from the beginning
            current_variable = 0
          else
            current_variable += 1
          end
        end

        # then, manage first actor having only one variable matching and go back to the first step
        while current_actor < variables_for_each_actor.length
          current_actor_key = variables_for_each_actor.keys[current_actor]
          if variables_for_each_actor[current_actor_key].count == 1
            current_variable_key = variables_for_each_actor[current_actor_key].first
            result[current_variable_key] = current_actor_key
            clean(variables_for_each_actor, actors_for_each_variable, result[current_variable_key], current_variable_key)
            # return to first step
            current_actor = 0
            break
          else
            current_actor += 1
          end
        end
        # then, manage the case when no actor has only one variable matching
        if current_actor >= variables_for_each_actor.length
          current_variable = 0
          current_variable_key = actors_for_each_variable.keys[current_variable]
          result[current_variable_key] = actors_for_each_variable[current_variable_key].first unless actors_for_each_variable[current_variable_key].nil?
          clean(variables_for_each_actor, actors_for_each_variable, result[current_variable_key], current_variable_key)
          # return to first step
        end

        # finally, manage the case when there's no more actor to match with variables
        if variables_for_each_actor.empty?
          actors_for_each_variable.keys.each do |variable_key|
            result[variable_key] = nil
          end
        end

      end
      return result.delete_if{|k,v|v.nil?}
    end

    private
    # clean
    # removes newly matched actor and variable from hashes
    # associating all possible actors for each variable and
    # all possible variables for each actor
    # @params:  - actors_hash, variables_hash, the hashes to clean
    #           - actor, variable, the values to remove
    def clean(actors_hash, variables_hash, actor, variable)
      # deleting actor from hash "actor => variables"
      actors_hash.delete(actor)
      # deleting actor for all remaining variables
      variables_hash.values.each {|ary| ary.delete(actor)}
      # removing current variable for all remaining actors
      actors_hash.values.each {|ary| ary.delete(variable)}
      # removing current variable from hash "variable => actors"
      variables_hash.delete(variable)
    end

  end

end
