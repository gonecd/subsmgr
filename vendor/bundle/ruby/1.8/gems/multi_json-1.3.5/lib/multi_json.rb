module MultiJson
	class DecodeError < StandardError
		attr_reader :data
		def initialize(message, backtrace, data)
			super(message)
			self.set_backtrace(backtrace)
			@data = data
		end
	end

	@adapter = nil

	REQUIREMENT_MAP = [
		["oj", :oj],
		["yajl", :yajl],
		["json", :json_gem],
		["json/pure", :json_pure]
	]

	class << self

		# The default adapter based on what you currently
		# have loaded and installed. First checks to see
		# if any adapters are already loaded, then checks
		# to see which are installed if none are loaded.
		def default_adapter
			return :oj if defined?(::Oj)
			return :yajl if defined?(::Yajl)
			return :json_gem if defined?(::JSON)

			REQUIREMENT_MAP.each do |(library, adapter)|
				begin
					require library
					return adapter
				rescue LoadError
					next
				end
			end

			Kernel.warn "[WARNING] MultiJson is using the default adapter (ok_json). We recommend loading a different JSON library to improve performance."
			:ok_json
		end
		# :nodoc:
		alias :default_engine :default_adapter

		# Get the current adapter class.
		def adapter
			return @adapter if @adapter
			self.use self.default_adapter
			@adapter
		end
		# :nodoc:
		alias :engine :adapter

		# Set the JSON parser utilizing a symbol, string, or class.
		# Supported by default are:
		#
		# * <tt>:oj</tt>
		# * <tt>:json_gem</tt>
		# * <tt>:json_pure</tt>
		# * <tt>:ok_json</tt>
		# * <tt>:yajl</tt>
		# * <tt>:nsjsonserialization</tt> (MacRuby only)
		def use(new_adapter)
			@adapter = load_adapter(new_adapter)
		end
		alias :adapter= :use
		# :nodoc:
		alias :engine= :use

		def load_adapter(new_adapter)
			case new_adapter
			when String, Symbol
				require "multi_json/adapters/#{new_adapter}"
				MultiJson::Adapters.const_get("#{new_adapter.to_s.split('_').map{|s| s.capitalize}.join('')}")
			when NilClass
				nil
			when Class
				new_adapter
			else
				raise "Did not recognize your adapter specification. Please specify either a symbol or a class."
			end
		end

		# Decode a JSON string into Ruby.
		#
		# <b>Options</b>
		#
		# <tt>:symbolize_keys</tt> :: If true, will use symbols instead of strings for the keys.
		# <tt>:adapter</tt> :: If set, the selected engine will be used just for the call.
		def load(string, options={})
			adapter = current_adapter(options)
			adapter.load(string, options)
		rescue adapter::ParseError => exception
			raise DecodeError.new(exception.message, exception.backtrace, string)
		end
		# :nodoc:
		alias :decode :load

		def current_adapter(options)
			if new_adapter = (options || {}).delete(:adapter)
				load_adapter(new_adapter)
			else
				adapter
			end
		end

		# Encodes a Ruby object as JSON.
		def dump(object, options={})
			adapter = current_adapter(options)
			adapter.dump(object, options)
		end
		# :nodoc:
		alias :encode :dump

	end

end
