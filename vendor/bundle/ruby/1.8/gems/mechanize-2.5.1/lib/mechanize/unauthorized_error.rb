class Mechanize::UnauthorizedError < Mechanize::ResponseCodeError

	attr_reader :challenges

	def initialize page, challenges, message
		super page, message
		@challenges = challenges
	end

	def to_s
		out = super

		if @challenges then
			realms = @challenges.map { |challenge| challenge.realm_name }.join ', '
			out << " -- available realms: #{realms}"
		end

		out
	end

end

