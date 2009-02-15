#
#--
# Copyright (c) 2006-2009, John Mettraux, OpenWFE.org
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# . Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# . Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# . Neither the name of the "OpenWFE" nor the names of its contributors may be
#   used to endorse or promote products derived from this software without
#   specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#++
#

#
# "made in Japan"
#
# John Mettraux at openwfe.org
#

require 'openwfe/exceptions'
require 'openwfe/expressions/flowexpression'
require 'openwfe/rudefinitions'


module OpenWFE

  #
  # A class storing bits (trees) of process definitions just
  # parsed. Upon application (apply()) these raw expressions get turned
  # into real expressions.
  #
  class RawExpression < FlowExpression

    #
    # A [static] method for creating new RawExpression instances.
    #
    def self.new_raw (fei, parent_id, env_id, app_context, raw_tree)

      re = self.new

      re.fei = fei
      re.parent_id = parent_id
      re.environment_id = env_id
      re.application_context = app_context
      re.attributes = nil
      re.children = []
      re.apply_time = nil

      re.raw_representation = raw_tree
      re
    end

    #
    # When a raw expression is applied, it gets turned into the
    # real expression which then gets applied.
    #
    def apply (workitem)

      exp_class, val = determine_real_expression_class

      expression = instantiate_real_expression(workitem, exp_class, val)

      expression.apply_time = Time.now
      expression.store_itself

      expression.apply(workitem)
    end

    #
    # This method is called by the expression pool when it is about
    # to launch a process, it will interpret the 'parameter' statements
    # in the process definition and raise an exception if the requirements
    # are not met.
    #
    def check_parameters (workitem)

      extract_parameters.each { |param| param.check(workitem) }
    end

    #--
    #def reply (workitem)
    # no implementation necessary
    #end
    #++

    def is_definition?

      get_expression_map.is_definition?(expression_name())
    end

    def expression_class

      get_expression_map.get_class(expression_name())
    end

    def definition_name

      (raw_representation[1]['name'] || raw_children.first).to_s
    end

    def expression_name

      raw_representation.first
    end

    #
    # Forces the raw expression to load the attributes and set them
    # in its @attributes instance variable.
    # Currently only used by FilterDefinitionExpression.
    #
    def load_attributes

      @attributes = raw_representation[1]
    end

    #
    # This method has been made public in order to have quick look
    # at the attributes of an expression before it's really
    # 'instantiated'.
    #
    # (overriden by ExpExpression)
    #
    def extract_attributes

      raw_representation[1]
    end

    protected

      #
      # Looks up a key as a variable or a participant.
      #
      def lookup (kind, key, underscore=false)

        val = (kind == :variable) ?
          lookup_variable(key) : get_participant_map.lookup_participant(key)

        return lookup(:participant, val) || lookup(:variable, val) \
          if kind == :variable and val.is_a?(String) # alias lookup

        return val, key if val

        return nil if underscore

        lookup(kind, OpenWFE::to_underscore(key), true)
      end

      #
      # Determines if this raw expression points to a classical
      # expression, a participant or a subprocess, or nothing at all...
      #
      def determine_real_expression_class

        exp_name = expression_name()

        val, key =
          lookup(:variable, exp_name) ||
          expression_class() ||
          lookup(:participant, exp_name)
            # priority to variables

        if val.is_a?(Array)

          [ SubProcessRefExpression, val ]

        elsif val.respond_to?(:consume)

          [ ParticipantExpression, key ]

        else

          [ val, nil ]
        end
      end

      def instantiate_real_expression (workitem, exp_class, val)

        raise "unknown expression '#{expression_name}'" unless exp_class

        exp = exp_class.new
        exp.fei = @fei
        exp.parent_id = @parent_id
        exp.environment_id = @environment_id
        exp.application_context = @application_context
        exp.attributes = extract_attributes()

        exp.raw_representation = @raw_representation
        exp.raw_rep_updated = @raw_rep_updated

        consider_tag(workitem, exp)
        consider_on_error(workitem, exp)
        consider_on_cancel(workitem, exp)

        if val
          class << exp
            attr_accessor :hint
          end
          exp.hint = val
        end # later sparing a variable/participant lookup

        exp
      end

      def extract_parameters

        r = []
        raw_representation.last.each do |child|

          next if OpenWFE::ExpressionTree.is_not_a_node?(child)

          name = child.first.to_sym
          next unless (name == :parameter or name == :param)

          attributes = child[1]

          r << Parameter.new(
            attributes['field'],
            attributes['match'],
            attributes['default'],
            attributes['type'])
        end
        r
      end

      #
      # Expressions can get tagged. Tagged expressions can easily
      # be cancelled (undone) or redone.
      #
      def consider_tag (workitem, new_expression)

        tagname = new_expression.lookup_string_attribute(:tag, workitem)

        return unless tagname

        ldebug { "consider_tag() tag is '#{tagname}'" }

        set_variable(tagname, Tag.new(self, workitem))
          #
          # keep copy of raw expression and workitem as applied

        new_expression.attributes['tag'] = tagname
          #
          # making sure that the value of tag doesn't change anymore
      end

      #
      # A small class wrapping a tag (a raw expression and the workitem
      # it received at apply time.
      #
      class Tag

        attr_reader :raw_expression, :workitem

        def flow_expression_id
          @raw_expression.fei
        end
        alias :fei :flow_expression_id

        def initialize (raw_expression, workitem)

          @raw_expression = raw_expression.dup
          @workitem = workitem.dup
        end
      end

      #
      # manages 'on-error' expression tags
      #
      def consider_on_error (workitem, new_expression)

        on_error = new_expression.lookup_string_attribute(:on_error, workitem)

        return unless on_error

        on_error = on_error.to_s

        handlers = lookup_variable('error_handlers') || []

        handlers << [ fei.dup, on_error ]
          # not using a hash to preserve insertion order
          # "deeper last"

        set_variable('error_handlers', handlers)

        new_expression.attributes['on_error'] = on_error
          #
          # making sure that the value of tag doesn't change anymore
      end

      #
      # manages 'on-cancel'
      #
      def consider_on_cancel (workitem, new_expression)

        on_cancel = new_expression.lookup_string_attribute(:on_cancel, workitem)

        return unless on_cancel

        new_expression.attributes['on_cancel'] = [ on_cancel, workitem.dup ]
          #
          # storing the on_cancel value (a participant name or a subprocess
          # name along with a copy of the workitem as applied among the
          # attributes of the new expression)
      end

      #
      # Encapsulating
      #   <parameter field="x" default="y" type="z" match="m" />
      #
      # Somehow I hate that param thing, Ruote is not a strongly typed language
      # ... Anyway Pat seems to use it.
      #
      class Parameter

        def initialize (field, match, default, type)

          @field = to_s(field)
          @match = to_s(match)
          @default = to_s(default)
          @type = to_s(type)
        end

        #
        # Will raise an exception if this param requirement is not
        # met by the workitem.
        #
        def check (workitem)

          raise(
            OpenWFE::ParameterException,
            "'parameter'/'param' without a 'field' attribute"
          ) unless @field

          field_value = workitem.attributes[@field]
          field_value = @default unless field_value

          raise(
            OpenWFE::ParameterException,
            "field '#{@field}' is missing"
          ) unless field_value

          check_match(field_value)

          enforce_type(workitem, field_value)
        end

        protected

          #
          # Used in the constructor to flatten everything to strings.
          #
          def to_s (o)
            o ? o.to_s : nil
          end

          #
          # Will raise an exception if it cannot coerce the type
          # of the value to the one desired.
          #
          def enforce_type (workitem, value)

            value = if not @type
              value
            elsif @type == 'string'
              value.to_s
            elsif @type == 'int' or @type == 'integer'
              Integer(value)
            elsif @type == 'float'
              Float(value)
            else
              raise
                "unknown type '#{@type}' for field '#{@field}'"
            end

            workitem.attributes[@field] = value
          end

          def check_match (value)

            return unless @match

            raise(
              OpenWFE::ParameterException,
              "value of field '#{@field}' doesn't match"
            ) unless value.to_s.match(@match)
          end
      end
  end

  private

    #
    # OpenWFE process definitions do use some
    # Ruby keywords... The workaround is to put an underscore
    # just before the name to 'escape' it.
    #
    # 'undo' isn't reserved by Ruby, but lets keep it in line
    # with 'do' and 'redo' that are.
    #
    KEYWORDS = [
      :if, :do, :redo, :undo, :print, :sleep, :loop, :break, :when
      #:until, :while
    ]

    #
    # Ensures the method name is not conflicting with Ruby keywords
    # and turn dashes to underscores.
    #
    def OpenWFE.make_safe (method_name)

      method_name = OpenWFE::to_underscore(method_name)

      KEYWORDS.include?(
        eval(":#{method_name}")) ? "_#{method_name}" : method_name
    end

    def OpenWFE.to_expression_name (method_name)

      method_name = method_name.to_s
      method_name = method_name[1..-1] if method_name[0, 1] == '_'
      method_name = OpenWFE::to_dash(method_name)
      method_name
    end

end

