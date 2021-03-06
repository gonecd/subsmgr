module Plugin
	LIST = ["Forom", "Podnapisi", "SeriesSub", "SousTitresEU", "TVSubs", "TVSubtitles", "Addicted", "Local", "MySource"]

	def constantize(kls)
		if kls != '' && const_defined?(kls)
			Plugin.const_get(kls)
		end
	end
	module_function :constantize


	class Base
		attr_accessor :current, :rank, :idx_candidat

		def get_from_source
			# Récupérer le sous titre et le mettre dans /tmp/Sub.srt
			#
			# Fonctions utiles :
			#		FileCache.get_srt(lien, referer = nil) -- stocke le srt disponible sur lien dans /tmp/Sub.srt
			#		FileCache.get_zip(lien, fichier, referer = nil) -- fichier étant le fichier à extraire du zip, la cible étant automatiquement /tmp/Sub.srt
		end

		# must be overloaded
		def do_search
			# doit retourner un tableau de lignes du type (les autres champs nécessaires sont remplis automatiquement)
			#		 new_ligne = WebSub.new
			#		 new_ligne.fichier = ""
			#		 new_ligne.date = ""
			#		 new_ligne.lien = ""
			#		 new_ligne.referer = ""
			[]
		end

		# ----------------------------
		# NOTHING TO CHANGE AFTER THIS
		# ----------------------------
		def initialize(current, rank, idx_candidat)
			self.current = current
			self.current.candidats ||= []
			self.rank = rank.to_f / 1000
			self.idx_candidat = idx_candidat
		end

		# retrieve and verify subtitle is valid, otherwise delete retrieved file
		def retrieve_subtitle
			File.unlink("/tmp/Sub.srt") if File.exists?("/tmp/Sub.srt")
			get_from_source
			return true if valid_subtitle?
			File.unlink("/tmp/Sub.srt") if File.exists?("/tmp/Sub.srt")
			return false
		end

		def valid_subtitle?
			content = File.exists?("/tmp/Sub.srt") ? File.read("/tmp/Sub.srt") : nil
			# empty file
			if content.blank?
				current.comment = "blank subtitle"
				Tools.logger.error "# SubsMgr Error # #{current.comment}"
				return false
			end
			
			# html file
			if content.match(/<(body|html)[^>]*>/im)
				current.comment = "html file found instead of real subtitles"
				Tools.logger.error "# SubsMgr Error # #{current.comment}"
				return false
			end
			
			true
		end
		

		# generic search
		def search_sub
			# Lister tous les candidats disponibles et remplir la structure @current.candidats
			start = Time.now
			count = marks = 0
			begin
				kls = self.class.name.split(':').last
				# la liste de resultats peut contenir des valeurs nil ainsi que des tableaux imbriqués
				# donc on remet tout à plat, on purge les nil, et on ajoute tout ce qui est commun
				# a toutes les entrées plutot que de le faire au moment du parsing (cela donne du code
				# un peu plus "basique" pour les plugins)
				list = (do_search || []).flatten.compact.collect do |item|
					item.calcul_confiance(self.current, self.rank)
					item.source = kls
					item
				end
				count = list.size
				marks = list.inject(0) { |sum, e| sum += e.confiant}
				self.current.candidats = self.current.candidats.concat(list)
			rescue Exception => e
				Tools.logger.error "# SubsMgr Error # search_sub #{self.class.name} [#{current.fichier}]: #{e.inspect}\n#{e.backtrace.join("\n")}"
				self.current.comment = "Pb dans le parsing #{self.class.name}"
			end
			
			self.current.send("#{self.class.field_name}=", count)
			# Mise à jour des stats
			# FIXME: remettre en place une fonction independante de l'UI
			Statistics.update_stats_search(self.class.index, start, marks, count) if count > -1
		end

		def self.field_name
			self.name.split(':').last.downcase
		end

		def self.index
			Plugin::LIST.index(self.name.split(':').last).to_i
		end

	end
end
