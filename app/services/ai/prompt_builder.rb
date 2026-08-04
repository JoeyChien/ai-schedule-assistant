module Ai
  class PromptBuilder
    def self.render(template_name, locals = {})
      template_path = Rails.root.join("prompts", "#{template_name}.txt.erb")

      template = ERB.new(File.read(template_path))

      context = Object.new

      locals.each do |key, value|
        context.instance_variable_set("@#{key}", value)

        context.define_singleton_method(key) do
          instance_variable_get("@#{key}")
        end
      end

      template.result(context.instance_eval { binding })
    end
  end
end
