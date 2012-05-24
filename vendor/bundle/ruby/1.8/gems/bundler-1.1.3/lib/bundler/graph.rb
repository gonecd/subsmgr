require 'set'
module Bundler
	class Graph
		GRAPH_NAME = :Gemfile

		def initialize(env, output_file, show_version = false, show_requirements = false, output_format = "png")
			@env							 = env
			@output_file			 = output_file
			@show_version			 = show_version
			@show_requirements = show_requirements
			@output_format		 = output_format

			@groups						 = []
			@relations				 = Hash.new {|h, k| h[k] = Set.new}
			@node_options			 = {}
			@edge_options			 = {}

			_populate_relations
		end

		attr_reader :groups, :relations, :node_options, :edge_options, :output_file, :output_format

		def viz
			GraphVizClient.new(self).run
		end

		private

		def _populate_relations
			relations = Hash.new {|h, k| h[k] = Set.new}
			parent_dependencies = _groups.values.to_set.flatten
			while true
				if parent_dependencies.empty?
					break
				else
					tmp = Set.new
					parent_dependencies.each do |dependency|
						child_dependencies = dependency.to_spec.runtime_dependencies.to_set
						relations[dependency.name] += child_dependencies.to_set
						@relations[dependency.name] += child_dependencies.map(&:name).to_set
						tmp += child_dependencies

						@node_options[dependency.name] = {:label => _make_label(dependency, :node)}
						child_dependencies.each do |c_dependency|
							@edge_options["#{dependency.name}_#{c_dependency.name}"] = {:label => _make_label(c_dependency, :edge)}
						end
					end
					parent_dependencies = tmp
				end
			end
			@relations
		end

		def _groups
			relations = Hash.new {|h, k| h[k] = Set.new}
			@env.current_dependencies.each do |dependency|
				dependency.groups.each do |group|
					relations[group.to_s].add(dependency)
					@relations[group.to_s].add(dependency.name)

					@node_options[group.to_s] ||= {:label => _make_label(group, :node)}
					@edge_options["#{group}_#{dependency.name}"] = {:label => _make_label(dependency, :edge)}
				end
			end
			@groups = relations.keys
			relations
		end

		def _make_label(symbol_or_string_or_dependency, element_type)
			case element_type.to_sym
			when :node
				if symbol_or_string_or_dependency.is_a?(Gem::Dependency)
					label = symbol_or_string_or_dependency.name.dup
					label << "\n#{symbol_or_string_or_dependency.to_spec.version.to_s}" if @show_version
				else
					label = symbol_or_string_or_dependency.to_s
				end
			when :edge
				label = nil
				if symbol_or_string_or_dependency.respond_to?(:requirements_list) && @show_requirements
					tmp = symbol_or_string_or_dependency.requirements_list.join(", ")
					label = tmp if tmp != ">= 0"
				end
			else
				raise ArgumentError, "2nd argument is invalid"
			end
			label
		end

		class GraphVizClient
			def initialize(graph_instance)
				@graph_name		 = graph_instance.class::GRAPH_NAME
				@groups				 = graph_instance.groups
				@relations		 = graph_instance.relations
				@node_options	 = graph_instance.node_options
				@edge_options	 = graph_instance.edge_options
				@output_file	 = graph_instance.output_file
				@output_format = graph_instance.output_format
			end

			def g
				require 'graphviz'
				@g ||= ::GraphViz.digraph(@graph_name, {:concentrate => true, :normalize => true, :nodesep => 0.55}) do |g|
					g.edge[:weight]		= 2
					g.edge[:fontname] = g.node[:fontname] = 'Arial, Helvetica, SansSerif'
					g.edge[:fontsize] = 12
				end
			end

			def run
				@groups.each do |group|
					g.add_node(
						group,
						{:style			=> 'filled',
						 :fillcolor => '#B9B9D5',
						 :shape			=> "box3d",
						 :fontsize	=> 16}.merge(@node_options[group])
					)
				end

				@relations.each do |parent, children|
					children.each do |child|
						if @groups.include?(parent)
							g.add_node(child, {:style => 'filled', :fillcolor => '#B9B9D5'}.merge(@node_options[child]))
							g.add_edge(parent, child, {:constraint => false}.merge(@edge_options["#{parent}_#{child}"]))
						else
							g.add_node(child, @node_options[child])
							g.add_edge(parent, child, @edge_options["#{parent}_#{child}"])
						end
					end
				end

				if @output_format.to_s == "debug"
					$stdout.puts g.output :none => String
					Bundler.ui.info "debugging bundle viz..."
				else
					begin
						g.output @output_format.to_sym => "#{@output_file}.#{@output_format}"
						Bundler.ui.info "#{@output_file}.#{@output_format}"
					rescue ArgumentError => e
						$stderr.puts "Unsupported output format. See Ruby-Graphviz/lib/graphviz/constants.rb"
						raise e
					end
				end
			end
		end
	end
end
