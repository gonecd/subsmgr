# encoding: utf-8
# SubsMgr.rb
# SubsMgr
#
# Created by Cyril DELAMARE on 31/01/09.
# Copyright (c) 2009 __MyCompanyName__. All rights reserved.
#

$LOAD_PATH << File.join(File.dirname(__FILE__), "common")
$LOAD_PATH << File.join(File.dirname(__FILE__), "plugin")

ENV['RUBYCOCOA_THREAD_HOOK_DISABLE'] = '1' # disable thread warning

require 'osx/cocoa'
require 'common'

Tools.logger.level = 0

class SubsMgr < OSX::NSWindowController
    # ------------------------------------------
    # Pointeurs sur les objets de l'IHM
    # ------------------------------------------
    
    ib_outlets :serie, :saison, :episode, :team, :infos, :liste, :listeseries, :image, :fileTarg, :repTarg
    ib_outlets :subs, :release, :subsNb, :subsTot, :roue, :barre, :confiance, :plusmoins, :source
    ib_outlets :bFiltre, :listestats, :bSupprCrochets, :bSupprAccolades, :bCommande
    ib_outlets :source1, :source2, :source3
    ib_outlets :refreshItem
    
    # Petits drapeaux d'erreurs
    ib_outlets :errSaison, :errEpisode, :errTeam, :errInfos, :errSerie
    
    # Ecran Préférences
    ib_outlets :pDirTorrent, :pDirSerie, :pDirBanner, :pDirSubs, :pDirTorrents, :pDirTorrentButton, :pDirSerieButton, :pDirBannerButton, :pDirSubsButton, :pDirTorrentsButton
    ib_outlets :pFileRule, :pDirRule, :pSepRule
    ib_outlets :pConfiance, :pSchedRefresh, :pSchedSearch, :pSchedProcess, :pCacheDepth, :pForomKey
    ib_outlets :listesources, :nomSource, :rankSource, :activeSource, :alertMessage
    ib_outlets :pMove, :pSupprCrochets, :pSupprAccolades, :pCommande
    
    # Fenêtres annexes
    ib_outlets :fenPref, :fenMain, :fenMovie, :fenStats, :fenInfos, :fenWait, :fenSource
    ib_outlets :cinema
    ib_outlets :ovliste, :ovimage, :ovcharge, :ovsubs
    ib_outlets :libSeries
    ib_outlets :vue
    
    # Boutons Live et Historiques
    ib_outlets :bSearch, :bAccept, :bClean, :bRollback, :bManual, :bNoSub
    ib_outlets :bTest, :bGoWeb, :bLoadSub, :bViewSub, :bDir
    ib_outlets :bCleanSerie, :bWebSerie, :bInfoSerie
    ib_outlets :bVlc
    
    # Filtres de la liste
    ib_outlets :bAll, :bAttente, :bTraites, :bErreurs
    
    # ------------------------------------------
    # Méthode d'initialisation
    # ------------------------------------------
    def awakeFromNib
        
        # Gestion des fenêtres
        @fenWait.makeKeyAndOrderFront_(self)
        
        # Initialisation des variables globales
        @allEpisodes = []
        @lignes = []
        @lignesinfos = []
        @lignessources = []
        @ligneslibrary = []
        @liste.dataSource = self
        @liste.setDelegate_(self)
        @ovliste.dataSource = self
        @listeseries.dataSource = self
        @listestats.dataSource = self
        @listesources.dataSource = self
        @serieSelectionnee = "."
        @spotFilter = ""
        @appPath = OSX::NSBundle.mainBundle.resourcePath.fileSystemRepresentation
        Icones.path = File.join(@appPath, "Icones")
        #@TimerRefresh = OSX::NSTimer
        
        # First run ? Fichier manquants ?
        FileUtils.makedirs(Common::PREF_PATH) unless File.exist?(Common::PREF_PATH)
        FileUtils.touch("#{Common::PREF_PATH}/SubsMgrHistory.csv") unless File.exist?("#{Common::PREF_PATH}/SubsMgrHistory.csv")
        FileUtils.touch("#{Common::PREF_PATH}/SubsMgrWatchlist.csv") unless File.exist?("#{Common::PREF_PATH}/SubsMgrWatchlist.csv")
        unless File.exist?("#{Common::PREF_PATH}/SubsMgrPrefs.plist")
            FileUtils.cp(File.join(@appPath, "SubsMgrPrefs.plist"), "#{Common::PREF_PATH}/SubsMgrPrefs.plist")
        end
        unless File.exist?("#{Common::PREF_PATH}/SubsMgrSeries.plist")
            FileUtils.cp(File.join(@appPath, "SubsMgrSeries.plist"), "#{Common::PREF_PATH}/SubsMgrSeries.plist")
        end
        
        # Initialisations des sources dans la fenêtre de préférences
        for i in Plugin::LIST
            new_ligne = Sources.new
            new_ligne.source = i
            new_ligne.image = Icones.list[i]
            new_ligne.active = 0
            new_ligne.rank = 0
            @lignessources << new_ligne
        end
        @listesources.reloadData
        PrefCancel(self)
        
        # Initialisations spécifiques pour les plugins
        Plugin::Forom.forom_key = @prefs["Automatism"]["Forom key"]
        Plugin::Local.local_path = @prefs["Directories"]["Subtitles"]
        
        # Initialisation des banières de séries
        @banner = Banner.new(@prefs["Directories"]["Banners"])
        
        # Initialisation des Statistiques
        StatsRAZ(self) unless File.exist?("#{Common::PREF_PATH}/SubsMgrStats.plist")
        StatsLoad()
        StatsRefresh(self)
        
        # Construction des listes de series et d'episodes
        Refresh(self)
        @fenWait.close()
        
        manageButtons("Clear")
    end
    
    def CheckForUdate()
    end
    
    def ShowReleaseNotes()
    end
    
    
    # ------------------------------------------
    # Fonctions de gestion des tableaux
    # ------------------------------------------
    def rowSelected
        @current = @lignes[@liste.selectedRow()]
        return unless @current
        
        begin
            clearResults()
            
            # Affichage de l'analyse du fichier source
            @serie.setStringValue_(@current.serie)
            @image.setImage(@banner.retrieve_for(@current.serie))
            @saison.setIntValue(@current.saison)
            @episode.setIntValue(@current.episode)
            @team.setStringValue_(@current.team)
            @infos.setStringValue_(@current.infos)
            
            # Construire les fichiers et répertoire Targets
            @repTarg.setStringValue(@current.repTarget)
            @fileTarg.setStringValue(@current.fileTarget)
            
            # On se posionne sur le meilleur sous titre trouvé, c'est à dire le 1er vu que
            # les candidats sont triés par ordre décroissant de confiance
            unless @current.candidats.blank?
                @subsTot.setIntValue_(@current.candidats.size)
                @subsNb.setIntValue_(@current.candidats.size)
                @plusmoins.setIntValue(1)
                ChangeInstance(self)
            end
            
            # Gestion de l'affichage des boutons
            if @current.status == "Traité"
                manageButtons("EpisodeTraité")
                else
                manageButtons("EpisodeAttente")
            end
            
            rescue Exception => e
            Tools.logger.error "# SubsMgr Error # rowSelected ["+@current.fichier+"] : "+e
            @current.comment = "Pb dans l'analyse du fichier"
        end
        @liste.reloadData
    end
    ib_action :rowSelected
    
    
    def serieSelected(sender)
        
        selectedLigne = @listeseries.selectedRow()
        @serieSelectionnee = @ligneslibrary[selectedLigne].serie
        @saisonSelectionnee = @ligneslibrary[selectedLigne].saison
        @URLTVdb = @ligneslibrary[selectedLigne].URLTVdb
        RaffraichirListe()
        @image.setImage(@ligneslibrary[selectedLigne].image)
        
        manageButtons("Library")
    end
    ib_action :serieSelected
    
    def filterSelected(sender)
        
        @bAll.setState_(false)
        @bAttente.setState_(false)
        @bErreurs.setState_(false)
        @bTraites.setState_(false)
        
        sender.setState_(true)
        
        #Relister(sender)
        RaffraichirListe()
        
    end
    ib_action :filterSelected
    
    def spotlightSelected(sender)
        @spotFilter = @bFiltre.stringValue().to_s
        RaffraichirListe()
    end
    ib_action :spotlightSelected
    
    def numberOfRowsInTableView(view)
        case view.description
            when @liste.description then @lignes.size
            when @listeseries.description then @ligneslibrary.size
            when @listestats.description then Statistics.lignes_stats.size
            when @ovliste.description then @lignesinfos.size
            when @listesources.description then @lignessources.size
            else
            $stderr.puts "Attention : view non identifiée dans numberOfRowsInTableView #{view.description}"
            @lignes.size
        end
    end
    
    def tableView_objectValueForTableColumn_row(view, column, index)
        case view.description
            when @liste.description
            ligne = @lignes[index]
            case column.identifier
                when 'Message' then ligne.comment
                when 'Confiance' then ligne.conf
                when 'None' then "-"
                else
                field = column.identifier.downcase
                ligne.send(field) if ligne.respond_to?(field)
            end
            when @listeseries.description
            ligne = @ligneslibrary[index]
            case column.identifier
                when 'serie' then ligne.image
                when /ep[0-9]+/im
                if ligne.episodes[column.identifier.gsub(/ep/im, '').to_i-1]
                    ligne.episodes[column.identifier.gsub(/ep/im, '').to_i-1]["Statut"]
                end
                else
                field = column.identifier.downcase
                ligne.send(field) if ligne.respond_to?(field)
            end
            when @listestats.description
            ligne = Statistics.lignes_stats[index]
            field = column.identifier.downcase
            ligne.send(field) if ligne.respond_to?(field)
            when @ovliste.description
            ligne = @lignesinfos[index]
            field = column.identifier.downcase
            ligne.send(field) if ligne.respond_to?(field)
            when @listesources.description
            ligne = @lignessources[index]
            case column.identifier
                when 'Ranking' then ligne.rank
                else
                field = column.identifier.downcase
                ligne.send(field) if ligne.respond_to?(field)
            end
            else
            puts "Attention : view non identifiée dans tableView_objectValueForTableColumn_row #{view.description}"
            nil
        end
    end

    def tableView_setObjectValue_forTableColumn_row(view, value, column, index)

        if (column.identifier == 'Active') then @lignessources[index].active = value.intValue end
        if (column.identifier == 'Ranking') then @lignessources[index].rank = value.intValue end
    end
    
    def tableView_shouldSelectRow(view, row)
        @liste.selectRowIndexes_byExtendingSelection_(OSX::NSIndexSet.indexSetWithIndex(row), false)
        rowSelected()
        return true
    end
    
    
    
    # ------------------------------------------
    # Methodes de récupération des données de base
    # ------------------------------------------
    def Refresh(sender)
        case @refreshItem.indexOfSelectedItem()
            when 0
            RelisterEpisodes()
            RelisterSeries()
            RelisterInfos()
            AnalyseInfosSaison()
            RaffraichirListe()
            when 2
            RelisterEpisodes()
            AnalyseInfosSaison()
            RaffraichirListe()
            when 3
            RelisterSeries()
            AnalyseInfosSaison()
            when 4
            RelisterInfos()
            AnalyseInfosSaison()
            else
            puts "Refresh : cas non implémenté"
        end
    end
    ib_action :Refresh
    
    def RelisterEpisodes
        # Vider la liste
        @allEpisodes.clear
        
        # Préparation des variables de traitement
        libCSV = {}
        case @prefs["Naming Rules"]["Separator"]
            when 0 then sep = "."
            when 1 then sep = " "
            when 2 then sep = "-"
            when 3 then sep = " - "
        end
        case @prefs["Naming Rules"]["Episodes"]
            when 0 then masque = "%s%ss%02de%02d"
            when 1 then masque = "%s%s%dx%02d"
            when 2 then masque = "%s%sS%02dE%02d"
            when 3 then masque = "%s%s%d%02d"
            when 4 then masque = "%s%sSaison %d Episode %02d.avi"
        end
        
        # Récupération des données dans le fichier CSV
        File.open("#{Common::PREF_PATH}/SubsMgrHistory.csv").each do |line|
            begin
                row = CSV.parse_line(line, ';')
                raise CSV::IllegalFormatError unless (row && row.size == 8)
                
                # On parse la liste des épisodes
                ext = row[3].split('.').last
                balise = sprintf(masque+"."+ext, row[0], sep, row[1], row[2])
                libCSV[balise] = {
                    "FichierSource" => row[3],
                    "FichierSRT" => row[4],
                    "Date" => row[5],
                    "AutoManuel" => row[6],
                    "Source" => row[7]
                }
                rescue CSV::IllegalFormatError
                $stderr.puts "# SubsMgr Error # Invalid CSV history line skipped:\n#{line}"
            end
        end
        
        # Récupération des torrents en attente de download
        if File.exist?(@prefs["Directories"]["Torrents"])
            Dir.chdir(@prefs["Directories"]["Torrents"])
            Dir.glob("*.torrent").each do |x|
                new_ligne = Ligne.new
                new_ligne.fichier = x
                new_ligne.date = File.mtime(x)
                new_ligne.status = "Unloaded"
                @allEpisodes << new_ligne
                
                # Mise à jour des infos calculées
                @current = new_ligne
                AnalyseTorrent(@current.fichier)
            end
        end
        
        # Récupération des fichiers en attente de traitement
        if File.exist?(@prefs["Directories"]["Download"])
            Dir.chdir(@prefs["Directories"]["Download"])
            Dir.glob("*.{avi,mkv,mp4,m4v}").each do |x|
                new_ligne = Ligne.new
                new_ligne.fichier = x
                new_ligne.date = File.mtime(x)
                new_ligne.status = "Attente"
                @allEpisodes << new_ligne
                
                # Mise à jour des infos calculées
                @current = new_ligne
                AnalyseFichier(@current.fichier)
                buildTargets()
            end
        end
        
        # Récupération des fichiers traités
        if File.exist?(@prefs["Directories"]["Series"])
            Dir.chdir(@prefs["Directories"]["Series"])
            Dir.glob("*/*/*.{avi,mkv,mp4,m4v}").each do |x|
                new_ligne = Ligne.new
                new_ligne.fichier = File.basename(x)
                new_ligne.date = File.mtime(x)
                new_ligne.status = "Traité"
                @allEpisodes << new_ligne
                
                # Mise à jour des infos calculées
                @current = new_ligne
                AnalyseEpisode(@current.fichier)
                buildTargets()
                
                # Mise à jour des infos d'historique si elle existent
                if libCSV[new_ligne.fichier] != nil
                    new_candid = WebSub.new
                    new_candid.fichier = libCSV[new_ligne.fichier]["FichierSRT"].to_s
                    new_candid.date = libCSV[new_ligne.fichier]["AutoManuel"]
                    new_candid.lien = libCSV[new_ligne.fichier]["Date"]
                    new_candid.source = libCSV[new_ligne.fichier]["Source"]
                    new_candid.referer = "None"
                    new_candid.calcul_confiance(@current)
                    
                    @current.candidats << new_candid
                    @current.fichier = libCSV[new_ligne.fichier]["FichierSource"]
                    AnalyseFichier(@current.fichier)
                    @current.conf = @current.candidats.first.confiant
                end
            end
        end
        
        # on trie sans tenir compte de la casse et des caractères spéciaux
        @allEpisodes.sort! {|x,y| x.fichier.gsub(/[^a-z0-9\s-]+/i, '').downcase <=> y.fichier.gsub(/[^a-z0-9\s-]+/i, '').downcase }
    end
    def RelisterSeries
        @ligneslibrary.clear
        
        # On ajoute la ligne "All series"
        new_ligne = Library.new
        new_ligne.image = Icones.list["All series"]
        new_ligne.serie = "."
        new_ligne.saison = 0
        new_ligne.URLTVdb = "http://www.thetvdb.com/"
        new_ligne.nbepisodes = ""
        new_ligne.episodes = []
        @ligneslibrary << new_ligne
        
        # On parse tous les épisodes pour construire la liste des séries
        @allEpisodes.each do |episode|
            # La série est-elle déjà listée ?
            dejaListee = @ligneslibrary.any? do |libitem|
                (episode.serie.to_s == "Error") or ( (libitem.serie == episode.serie.to_s.downcase) and (libitem.saison == episode.saison) )
            end
            
            # Ajout de la série dans la liste
            unless dejaListee
                new_ligne = Library.new
                new_ligne.serie = episode.serie.to_s.downcase
                new_ligne.saison = episode.saison
                new_ligne.image = @banner.retrieve_for(episode.serie)
                new_ligne.episodes = []
                
                @ligneslibrary << new_ligne
            end
        end
 
        # On ajoute les series de la watchlist
        File.open("#{Common::PREF_PATH}/SubsMgrWatchlist.csv").each do |line|
            begin
                row = CSV.parse_line(line,';')
                raise CSV::IllegalFormatError unless (row && row.size == 2)
                
                # La s√©rie est-elle deja listee ?
                dejaListee = @ligneslibrary.any? do |libitem|
                    (libitem.serie == row[0].to_s.downcase) and (libitem.saison == row[1].to_i)
                end
                
                # Ajout de la serie dans la liste
                unless dejaListee
                    new_ligne = Library.new
                    new_ligne.serie = row[0].to_s.downcase
                    new_ligne.saison = row[1].to_i
                    new_ligne.image = @banner.retrieve_for(row[0].to_s.downcase)
                    new_ligne.episodes = []
                    
                    @ligneslibrary << new_ligne
                end
                
                
                rescue CSV::IllegalFormatError
                $stderr.puts "# SubsMgr Error # Invalid CSV watchlist line skipped:\n#{line}"
            end
        end
        
        @ligneslibrary.sort! {|x,y| x.serie+x.saison.to_s <=> y.serie+y.saison.to_s }
        
        # On ajoute la ligne "Errors"
        new_ligne = Library.new
        new_ligne.image = Icones.list["Erreurs"]
        new_ligne.serie = "Error"
        new_ligne.saison = 0
        new_ligne.URLTVdb = "http://www.thetvdb.com/"
        new_ligne.nbepisodes = ""
        new_ligne.episodes = []
        @ligneslibrary << new_ligne
        
        @listeseries.reloadData()
    end
    def RelisterInfos()
        
        @ligneslibrary.each do |maserie|
            if maserie.serie == "." or maserie.serie == "Error" then next end
            
            # Recherche de la page de la saison sur TheTVdb
            monURL = "http://www.thetvdb.com/?tab=series&id=#{@banner.id_for(maserie.serie)}"
            if monURL == "http://www.thetvdb.com/?tab=series&id=0" then next end
            doc = FileCache.get_html(monURL)
            doc.search("a.seasonlink").each do |k|
                if k.text.to_s == maserie.saison.to_s
                    monURL = "http://www.thetvdb.com"+k[:href].to_s
                    maserie.URLTVdb = monURL
                end
            end
            
            # Lecture des épisodes
            maserie.episodes = []
            numero = titre = diffusion = nil
            
            doc = FileCache.get_html(monURL)
            doc.search("table#listtable tr td").each_with_index do |k, index|
                next unless k['class'].match(/odd|even/im)
                case index.modulo(4)
                    when 0 then numero = k.text.to_i
                    when 1 then titre = k.text
                    when 2 then diffusion = k.text
                    when 3 then maserie.episodes << {"Episode" => numero, "Titre" => titre, "Diffusion" => diffusion, "Statut" => nil}
                end
            end
            
            maserie.nbepisodes = maserie.episodes.size()
        end
        @listeseries.reloadData()
    end
    def RaffraichirListe
        
        @lignes.clear
        clearResults
        
        totalEpisodes = @allEpisodes.size
        for i in (0..totalEpisodes-1)
            episode = @allEpisodes[i]
            
            if @serieSelectionnee == "."
                if episode.fichier.to_s.downcase.match(@spotFilter.downcase)
                    if (@bAll.state == 1)
                        @lignes << episode
                        elsif (@bTraites.state == 1) and (episode.status == "Traité")
                        @lignes << episode
                        elsif (@bAttente.state == 1) and (episode.status == "Attente")
                        @lignes << episode
                        elsif (@bErreurs.state == 1) and (episode.status != "Traité") and (episode.comment != "")
                        @lignes << episode
                    end
                end
                else
                if episode.serie.downcase.match(@serieSelectionnee.downcase) and episode.serie.downcase.match(@spotFilter.downcase) and episode.saison == @saisonSelectionnee
                    if (@bAll.state == 1)
                        @lignes << episode
                        elsif (@bTraites.state == 1) and (episode.status == "Traité")
                        @lignes << episode
                        elsif (@bAttente.state == 1) and (episode.status == "Attente")
                        @lignes << episode
                        elsif (@bErreurs.state == 1) and (episode.status != "Traité") and (episode.comment != "")
                        @lignes << episode
                    end
                end
            end
            
        end
        
        @liste.reloadData()
    end
    
    def manageButtons(modeAffichage)
        # On efface tous les boutons
        @bSearch.setHidden(true)
        @bAccept.setHidden(true)
        @bManual.setHidden(true)
        @bRollback.setHidden(true)
        @bClean.setHidden(true)
        @bNoSub.setHidden(true)
        
        @bLoadSub.setHidden(true)
        @bGoWeb.setHidden(true)
        @bViewSub.setHidden(true)
        @bTest.setHidden(true)
        @bDir.setHidden(true)
        
        @bCleanSerie.setHidden(true)
        @bWebSerie.setHidden(true)
        @bInfoSerie.setHidden(true)
        
        case modeAffichage
            when "Episodes" # Mode Episodes
            @bSearch.setHidden(false)
            @bAccept.setHidden(false)
            @bManual.setHidden(false)
            @bRollback.setHidden(false)
            @bClean.setHidden(false)
            @bNoSub.setHidden(false)
            
            if @source.stringValue() != ""
                @bLoadSub.setHidden(false)
                @bGoWeb.setHidden(false)
                @bViewSub.setHidden(false)
                @bTest.setHidden(false)
            end
            if (@fileTarg.stringValue() != "") and (@fileTarg.stringValue() != "Error s00e00")
                @bDir.setHidden(false)
            end
            when "EpisodeTraité"
            @bRollback.setHidden(false)
            @bClean.setHidden(false)
            
            if (@fileTarg.stringValue() != "") and (@fileTarg.stringValue() != "Error s00e00")
                @bDir.setHidden(false)
            end
            when "EpisodeAttente"
            @bSearch.setHidden(false)
            @bAccept.setHidden(false)
            @bManual.setHidden(false)
            @bNoSub.setHidden(false)
            
            if @source.stringValue() != ""
                @bLoadSub.setHidden(false)
                @bGoWeb.setHidden(false)
                @bViewSub.setHidden(false)
                @bTest.setHidden(false)
            end
            if (@fileTarg.stringValue() != "") and (@fileTarg.stringValue() != "Error s00e00")
                @bDir.setHidden(false)
            end
            when "Library" # Mode Library
            @bCleanSerie.setHidden(false)
            @bWebSerie.setHidden(false)
            @bInfoSerie.setHidden(false)
        end
    end
    def clearResults()
        # Vider les champs
        @release.setStringValue_("")
        @subs.setStringValue_("")
        @subsTot.setIntValue_(0)
        @subsNb.setIntValue_(0)
        @plusmoins.setIntValue(0)
        @serie.setStringValue_("")
        @saison.setStringValue_("")
        @episode.setStringValue_("")
        @team.setStringValue_("")
        @source.setStringValue_("")
        @infos.setStringValue_("")
        @fileTarg.setStringValue_("")
        @repTarg.setStringValue_("")
        @confiance.setIntValue(0)
        @image.setImage(@ligneslibrary[0].image)
    end
    def buildTargets()
        begin
            # Définition du répertoire cible
            case @prefs["Naming Rules"]["Directories"]
                when 0 then @current.repTarget = @prefs["Directories"]["Series"]+@current.serie+"/Saison "+@current.saison.to_s+"/"
                when 1 then @current.repTarget = @prefs["Directories"]["Series"]+@current.serie+"/"
                when 2 then @current.repTarget = @prefs["Directories"]["Series"]
            end
            
            # Définition du fichier cible
            case @prefs["Naming Rules"]["Separator"]
                when 0 then sep = "."
                when 1 then sep = " "
                when 2 then sep = "-"
                when 3 then sep = " - "
            end
            
            case @prefs["Naming Rules"]["Episodes"]
                when 0 then masque = "%s%ss%02de%02d"
                when 1 then masque = "%s%s%dx%02d"
                when 2 then masque = "%s%sS%02dE%02d"
                when 3 then masque = "%s%s%d%02d"
                when 4 then masque = "%s%sSaison %d Episode %02d"
            end
            
            @current.fileTarget = sprintf(masque, @current.serie, sep, @current.saison, @current.episode).gsub(/[\/:]+/, ', ').squish
            
            rescue Exception=>e
            Tools.logger.error "# SubsMgr Error # buildTargets ["+@current.fichier+"] : "+e
            @current.comment = "Pb dans l'analyse du fichier"
            
        end
    end
    
    def AnalyseFichier(chaine)
        begin
            # dans l'ordre du plus précis au moins précis (en particulier le format 101 se telescope avec les autres infos du type 720p ou x264)
            
            # Format s01e02 ou variantes (s1e1, s01e1, s1e01)
            temp = chaine.match(/(.*?).s([0-9]{1,2})[\._-]?e([0-9]{1,2})([\._\s-].*)*\.(avi|mkv|mp4|m4v)/i)
            # Format s01e22e23 ou variantes (s1e1, s01e1, s1e01)
            temp = chaine.match(/(.*?).s([0-9]{1,2})e([0-9]{1,2})[e_-][0-9]{1,2}([\._\s-].*)*\.(avi|mkv|mp4|m4v)/i) if temp.blank?
            # Format 1x02 ou 01x02
            temp = chaine.match(/(.*?).([0-9]{1,2})x([0-9]{1,2})([\._\s-].*)*\.(avi|mkv|mp4|m4v)/i) if temp.blank?
            # Format 102
            temp = chaine.match(/(.*?).([0-9]{1,2})([0-9]{2})([\._\s-].*)*\.(avi|mkv|mp4|m4v)/i) if temp.blank?
            
            if temp.blank?
                @current.serie = "Error"
                @current.saison = 0
                @current.episode = 0
                @current.team = "Error"
                @current.infos = "Error"
                if chaine.match(/vost|vostf|vostfr/im)
                    @current.comment = "Les sous-titres sont codés en dur!"
                    else
                    @current.comment = "Format non reconnu"
                end
                return
            end
            
            # On range
            @current.serie = temp[1].to_s.gsub(/\./, ' ').to_s.strip
            @current.saison = temp[2].to_i
            @current.episode = temp[3].to_i
            
            # on vire l'annee du nom de la serie si elle est la
            @current.serie = @current.serie.gsub(/(2011|2012|2013|2014|2015)/, '').to_s.strip
            
            # et on traite les infos correctement pour eliminer l'eventuel titre d'épisode
            infos = temp[4].to_s.split('-')
            
            # la team est toujours après le dernier tiret, suivi eventuellement d'un provider)
            (team, provider) = infos.pop.to_s.split(/\./, 2)
            @current.team = team.to_s
            @current.provider = provider.to_s.gsub(/[\[\]]+/im, '')
            
            # on peut maintenant récupérer les vrais infos
            infos = infos.join("-").to_s
            if (m = infos.match(/^.*?((REPACK|PROPER|720p|HDTV|PDTV|WSR)\.(.+))/im))
                @current.infos = m[1].gsub(/(xvid|divx|x264).*/im, '').gsub(/(^[^a-z0-9]+|[^a-z0-9]$)/im, '').strip
                else
                @current.infos = infos.gsub(/(^[^a-z0-9]+|[^a-z0-9]$)/im, '').gsub(/([\. -]?(xvid|divx|x264)[\. -]?)/im, '').strip
            end
            @current.infos << ".#{@current.provider}" if (@current.provider != '')
            
            if chaine.match(/720p/im)
                @current.format = '720p'
                # dans les sous-titres, ils ne reprécisent pas hdtv si c'est du 720p, cela va de soit a priori
                @current.infos.gsub!(/720p.hdtv/im, '720p')
            end
            
            rescue Exception=>e
            Tools.logger.error "# SubsMgr Error # AnalyseFichier [#{@current.fichier}] : #{e.inspect}"
            #Tools.logger.error "# SubsMgr Error # AnalyseFichier [#{@current.fichier}] : #{e.inspect}\n#{e.backtrace[0..10].join("\n")}"
            @current.serie = "Error"
            @current.saison = 0
            @current.episode = 0
            @current.infos = "Error"
            @current.team = "Error"
            @current.comment = "Pb dans l'analyse du fichier"
        end
        @current
    end
    def AnalyseTorrent(chaine)
        begin
            # On catche
            if chaine.match(/(.*) — [0-9]x[0-9][0-9].torrent/) # Format 1x02
                temp = chaine.scan(/(.*) — ([0-9]*[0-9])x([0-9][0-9]).torrent/)
                else
                @current.serie = "Error"
                @current.saison = 0
                @current.episode = 0
                @current.infos = ""
                @current.team = ""
                @current.comment = "Format non reconnu"
                return
            end
            
            # On range
            @current.serie = temp[0][0].gsub(/\./, ' ').to_s.strip
            @current.saison = temp[0][1].to_i
            @current.episode = temp[0][2].to_i
            @current.infos = ""
            @current.team = ""
            
            rescue Exception=>e
            puts "# SubsMgr Error # AnalyseTorrent [#{@current.fichier}] : #{e}\n#{e.backtrace.join("\n")}"
            @current.serie = "Error"
            @current.saison = 0
            @current.episode = 0
            @current.infos = ""
            @current.team = ""
            @current.comment = "Pb dans l'analyse du fichier"
            
        end
    end
    def AnalyseEpisode(chaine)
        begin
            # On catche
            if chaine.match(/(.*).[Ss][0-9][0-9][Ee][0-9][0-9].*/) # Format S01E02 ou s01e02
                temp = chaine.scan(/(.*).[Ss]([0-9]*[0-9])[Ee]([0-9][0-9]).(avi|mkv|mp4|m4v)/)
                else
                @current.serie = "Error"
                @current.saison = 0
                @current.episode = 0
                @current.infos = ""
                @current.team = ""
                @current.comment = "Format non reconnu"
                return
            end
            
            # On range
            @current.serie = temp[0][0].gsub(/\./, ' ').to_s.strip
            @current.saison = temp[0][1].to_i
            @current.episode = temp[0][2].to_i
            @current.infos = ""
            @current.team = ""
            
            rescue Exception=>e
            puts "# SubsMgr Error # AnalyseEpisode ["+@current.fichier+"] : "+e
            @current.serie = "Error"
            @current.saison = 0
            @current.episode = 0
            @current.infos = ""
            @current.team = ""
            @current.comment = "Pb dans l'analyse du fichier"
            
        end
    end
    
    def AnalyseInfosSaison()
        
        @ligneslibrary.each do |maserie|
            if maserie.serie == "." or maserie.serie == "Error" then next end
            
            # Analyse des épisodes de la saison
            maserie.episodes.each do |myepisode|
                begin
                    if Date.parse(myepisode["Diffusion"]) < Date.today()
                        myepisode["Statut"] = Icones.list["Aired"]
                        
                        subtitled = @allEpisodes.any? do |eps|
                            (eps.serie.to_s.downcase == maserie.serie) and (eps.saison == maserie.saison) and (eps.episode == myepisode["Episode"]) and (eps.status == "Traité")
                        end
                        
                        vidloaded = @allEpisodes.any? do |eps|
                            (eps.serie.to_s.downcase == maserie.serie) and (eps.saison == maserie.saison) and (eps.episode == myepisode["Episode"]) and (eps.status == "Attente")
                        end
                        
                        torrentloaded = @allEpisodes.any? do |eps|
                            (eps.serie.to_s.downcase == maserie.serie) and (eps.saison == maserie.saison) and (eps.episode == myepisode["Episode"]) and (eps.status == "Unloaded")
                        end
                        
                        if subtitled then myepisode["Statut"] = Icones.list["Subtitled"] end
                        if vidloaded then myepisode["Statut"] = Icones.list["VideoLoaded"] end
                        if torrentloaded then myepisode["Statut"] = Icones.list["TorrentLoaded"] end
                        else
                        myepisode["Statut"] = Icones.list["NotAired"]
                        maserie.status = Icones.list["NotAired"]
                    end
                    
                    rescue Exception
                    myepisode["Statut"] = Icones.list["NotAired"]
                    maserie.status = Icones.list["NotAired"]
                end
            end
            
            # Calcul du statut global de la saison
            maserie.status = Icones.list["Subtitled"]
            
            vidloaded = maserie.episodes.any? do |eps| (eps["Statut"] == Icones.list["VideoLoaded"]) end
            if vidloaded then maserie.status = Icones.list["VideoLoaded"] end
            
            torrentloaded = maserie.episodes.any? do |eps| (eps["Statut"] == Icones.list["TorrentLoaded"]) end
            if torrentloaded then maserie.status = Icones.list["TorrentLoaded"] end
            
            aired = maserie.episodes.any? do |eps| (eps["Statut"] == Icones.list["Aired"]) end
            if aired then maserie.status = Icones.list["Aired"] end
            
            notaired = maserie.episodes.any? do |eps| (eps["Statut"] == Icones.list["NotAired"]) end
            if notaired then maserie.status = Icones.list["NotAired"] end
        end
        
    end
    
    # Méthodes des boutons de gestion des versions de sous-titres
    def ChangeInstance (sender)
        if @plusmoins.intValue > @subsTot.intValue
            @plusmoins.setIntValue(@subsTot.intValue)
            elsif @plusmoins.intValue < 1
            @plusmoins.setIntValue(1)
            else
            # Changer le sous titre affiché
            candidat = @current.candidats[@plusmoins.intValue-1]
            
            @subsNb.setIntValue(@plusmoins.intValue)
            @subs.setStringValue(candidat.fichier)
            @release.setStringValue(candidat.date)
            @confiance.setIntValue(candidat.confiant)
            @source.setStringValue(candidat.source)
            @errSerie.setHidden(candidat.valid_serie?)
            @errSaison.setHidden(candidat.valid_saison?)
            @errEpisode.setHidden(candidat.valid_episode?)
            @errTeam.setHidden(candidat.valid_team?)
            @errInfos.setHidden(candidat.valid_info?)
        end
    end
    ib_action :ChangeInstance
    
    
    
    # ------------------------------------------
    # Methodes des timers de gestion automatique
    # ------------------------------------------
    def ScheduledRefresh(sender)
        puts "# SubsMgr Info # ScheduledRefresh Started"
        
        @refreshItem.selectItemAtIndex(0)
        Refresh(sender)
        
        puts "# SubsMgr Info # ScheduledRefresh Finished"
    end
    
    def ScheduledSearch(sender)
        puts "# SubsMgr Info # ScheduledSearch Started"
        
        
        
        puts "# SubsMgr Info # ScheduledSearch Finished"
    end
    
    def ScheduledProcess(sender)
        puts "# SubsMgr Info # ScheduledProcess Started"
        
        
        
        puts "# SubsMgr Info # ScheduledProcess Finished"
    end
    
    
    # ------------------------------------------
    # Methodes de traitement des sous titres
    # ------------------------------------------
    def ManageAll(sender)
        totalEpisodes=numberOfRowsInTableView(@liste)
        @barre.setMinValue(0)
        @barre.setMaxValue(totalEpisodes)
        @barre.setIntValue(0)
        @barre.setHidden(false)
        @barre.displayIfNeeded
        text = ""
        
        for i in (0..totalEpisodes-1)
            @liste.selectRowIndexes_byExtendingSelection_(OSX::NSIndexSet.indexSetWithIndex(i), false)
            rowSelected
            if @current.status != "Traité"
                if @current.conf >= (@prefs["Automatism"]["Min confidence"]+1)
                    AcceptSub(@team)
                    text = text+@current.fileTarget+"\n"
                end
            end
            @barre.setIntValue(i)
            @barre.displayIfNeeded
            
        end
        
        RaffraichirListe()
        
        # Raffraichissement des statistiques
        StatsRefresh(self)
        
        # Message de synthèse des épisodes traités
        alert = OSX::NSAlert.alloc().init()
        alert.setMessageText_("Episodes traités :")
        alert.setInformativeText_(text)
        alert.setAlertStyle_(OSX::NSInformationalAlertStyle)
        alert.runModal();
        @barre.setHidden(true)
    end
    ib_action :ManageAll
    
    def AcceptSub(sender)
        
        if (@current.repTarget == "") or (@current.fileTarget == "") then return end
        
        # Mettre à jour la liste
        @current.processed!
        
        start = Time.now
        
        if @current.candidats[@plusmoins.intValue-1].blank?
            # no subs available
            return false
            elsif @current.candidats[@plusmoins.intValue-1].lien != ""
            # Récupération du sous titre
            if GetSub()
                # Rangement des fichiers
                CheckArbo()
                ManageFiles()
                
                # Mise à jour du fichier de suivi
                updateHistory(sender)
                else
                $stderr.puts "Sub not accepted - invalid sub file detected - Canceled"
                return false
            end
        end
        
        src = @current.candidats[@plusmoins.intValue-1].source
        if (kls = Plugin.constantize(src))
            Statistics.update_stats_accept(kls.index, start, sender)
            @current.send("#{src.downcase}=", "©")
            else
            $stderr.puts "Je suis perdu, j'ai jamais entendu parlé de #{src}!"
        end
        
        
        # Raffraichissement de la liste
        if sender != @team
            @current.comment = "Traité en Manuel"
            select_next_line
            
            # Raffraichissement des statistiques
            StatsRefresh(self)
            else
            @current.comment = "Traité en Automatique"
        end
    end
    ib_action :AcceptSub
    
    def select_next_line(refresh_only = false)
        idx = @liste.selectedRow()
        if (@bAttente.state == 1) && !refresh_only
            @lignes.delete(@current)
            else
            # nothing cleaned so let's move to next entry
            idx += 1
        end
        
        @liste.reloadData()
        if (numberOfRowsInTableView(@liste) > 0)
            if (numberOfRowsInTableView(@liste)>=idx)
                @liste.selectRowIndexes_byExtendingSelection_(OSX::NSIndexSet.indexSetWithIndex(idx), false)
                else
                @liste.selectRowIndexes_byExtendingSelection_(OSX::NSIndexSet.indexSetWithIndex(0), false)
            end
            rowSelected()
        end
    end
    
    def ManageFiles()
        if File.exist?("/tmp/Sub.srt")
            
            # Déplacement du film
            ext = @current.fichier.split('.').last
            if (@prefs["Subs management"]["Move"] == 0)
                FileUtils.cp(@prefs["Directories"]["Download"]+@current.fichier, @current.repTarget+@current.fileTarget+".#{ext}")
                else
                FileUtils.mv(@prefs["Directories"]["Download"]+@current.fichier, @current.repTarget+@current.fileTarget+".#{ext}")
            end
            
            # Déplacement du sous titre
            FileUtils.mv("/tmp/Sub.srt", @current.repTarget+@current.fileTarget+".srt")
            
            else
            puts "Problem pour :" + @current.candidats[@plusmoins.intValue-1].source + " - " + @current.fileTarget
        end
    end
    def CheckArbo()
        # Créer l'arborescence si nécessaire
        if File.exist?(@current.repTarget) == false
            FileUtils.makedirs(@current.repTarget)
        end
    end
    
    
    
    # ------------------------------------------
    # Fonctions de recherche des SousTitres
    # ------------------------------------------
    def SearchAll(sender)
        totalEpisodes = numberOfRowsInTableView(@liste)
        @barre.setMinValue(0)
        @barre.setMaxValue(totalEpisodes)
        @barre.setIntValue(0)
        @barre.setHidden(false)
        @barre.displayIfNeeded
        
        for i in (0..totalEpisodes-1)
            @liste.selectRowIndexes_byExtendingSelection_(OSX::NSIndexSet.indexSetWithIndex(i), false)
            rowSelected
            if @current.status != "Traité"
                SearchSub(sender)
            end
            
            # Raffraichissement de la fenêtre
            @liste.displayIfNeeded
            @barre.setIntValue(i)
            @barre.displayIfNeeded
        end
        
        # Raffraichissement des statistiques
        StatsRefresh(self)
        @barre.setHidden(true)
    end
    ib_action :SearchAll
    
    def SearchSub(sender)
        return if @current.serie == "Error"
        
        @roue.startAnimation(self)
        @current.reset!
        
        # Recherche pour les sources actives en // (enfin si ruby supporte les threads !)
        threads = []
        Plugin::LIST.each do |p|
            if (plugin = Plugin.constantize(p))
                if @lignessources[plugin.index] && @lignessources[plugin.index].active.to_i == 1
                    threads << Thread.new(plugin) { |e|
                        e.new(@current, @lignessources[e.index].rank, @plusmoins.intValue-1).search_sub
                    }
                end
            end
        end
        # et on attend que tout le monde ait terminé
        threads.each {|t| t.join }
        
        @subsTot.setIntValue_(@current.candidats.size())
        @subsNb.setIntValue_(@current.candidats.size())
        @plusmoins.setIntValue(@current.candidats.size())
        
        # Positionnement sur le meilleur candidat
        @current.conf = 0
        @current.candidats = @current.candidats.sort_by {|x| [-x.score, x.errors[:team] ? 1 : 0]}
        if @current.candidats.size>0
            @plusmoins.setIntValue(1)
            @current.conf = @current.candidats.first.confiant.to_i
            ChangeInstance(self)
        end
        
        @liste.reloadData
        
        @roue.stopAnimation(self)
        rowSelected
    end
    ib_action :SearchSub
    
    def ManualSearch(sender)
        # Récupération des valeurs saisies dans l'IHM
        @current.serie = @serie.stringValue().to_s
        @current.saison = @saison.intValue().to_i
        @current.episode = @episode.intValue().to_i
        @current.infos = @infos.stringValue().to_s
        @current.team = @team.stringValue().to_s
        
        # Construire les fichiers et répertoire Targets
        buildTargets()
        @repTarg.setStringValue(@current.repTarget)
        @fileTarg.setStringValue(@current.fileTarget)
        
        # et on lance la recherche
        SearchSub(sender)
        
        manageButtons("EpisodeAttente")
    end
    ib_action :ManualSearch
    
    
    # ------------------------------------------
    # Fonctions de gestion de l'historique
    # ------------------------------------------
    def HistoRollback (sender)
        begin
            # Déplacer les fichiers
            ext = @current.fichier.split('.').last
            FileUtils.mv(@current.repTarget+@current.fileTarget+".#{ext}", @prefs["Directories"]["Download"]+@current.fichier)
            FileUtils.rm(@current.repTarget+@current.fileTarget+".srt")
            
            rescue Exception=>e
            puts "# SubsMgr Error # HistoRollback ["+@current.fichier+"] : "+e
        end
        
        # Mettre à jour l'historique
        HistoClean(sender)
        
        # Mettre à jour la liste
        @current.pending!
        
        rowSelected()
        RaffraichirListe()
    end
    ib_action :HistoRollback
    
    def HistoClean (sender)
        
        begin
            outfile = File.open('/tmp/csvout', 'wb')
            CSV::Reader.parse(File.open("#{Common::PREF_PATH}/SubsMgrHistory.csv"),';') do |row|
                if row[3] != @current.fichier
                    CSV::Writer.generate(outfile, ';') do |csv|
                        csv << row
                    end
                end
            end
            outfile.close
            FileUtils.mv('/tmp/csvout', "#{Common::PREF_PATH}/SubsMgrHistory.csv")
            
            rescue Exception=>e
            puts "# SubsMgr Error # HistoClean ["+@current.fichier+"] : "+e
        end
        
        if sender.description() == @bClean.description()
            @lignes.delete(@current)
            @allEpisodes.delete(@current)
            @liste.reloadData()
        end
    end
    ib_action :HistoClean
    
    def updateHistory(sender)
        # Identification du cas
        if sender == @team
            typeGestion = "Automatique"
            elsif sender == @bLoadSub
            toFichier = @current.serie+";"+@current.saison.to_s+";"+@current.episode.to_s+";"+@current.fichier+";None;None;Manuel;None\n"
            fichierCSV = File.open("#{Common::PREF_PATH}/SubsMgrHistory.csv",'a+')
            fichierCSV << toFichier
            fichierCSV.close
            return
            else
            typeGestion = "Manuel"
        end
        
        # Mise à jour du fichier de suivi
        toFichier = @current.serie+";"+@current.saison.to_s+";"+@current.episode.to_s+";"+@current.fichier+";"+@current.candidats[@plusmoins.intValue-1].fichier+";"+@current.candidats[@plusmoins.intValue-1].date+";"+typeGestion+";"+@current.candidats[@plusmoins.intValue-1].source+"\n"
        fichierCSV = File.open("#{Common::PREF_PATH}/SubsMgrHistory.csv",'a+')
        fichierCSV << toFichier
        fichierCSV.close
    end
    
    
    # ------------------------------------------
    # Fonctions de Statistiques
    # ------------------------------------------
    def Statistiques(sender)
        @fenStats.makeKeyAndOrderFront_(sender)
    end
    ib_action :Statistiques
    
    def StatsLoad
        @lignesstats = Statistics.load
        @listestats.reloadData
    end
    
    def StatsRAZ(sender)
        FileUtils.cp(File.join(@appPath, "SubsMgrStats.plist"), "#{Common::PREF_PATH}/SubsMgrStats.plist")
        StatsLoad()
        # Raffraichissement des statistiques
        StatsRefresh(self)
    end
    ib_action :StatsRAZ
    
    def StatsRefresh(sender)
        @lignesstats = Statistics.refresh
        Statistics.save
        @listestats.reloadData
    end
    ib_action :StatsRefresh
    
    
    # ------------------------------------------
    # Fonctions liées aux sous-titres
    # ------------------------------------------
    def Tester(sender)
        if @current.candidats[@plusmoins.intValue-1].lien != ""
            # Récupération du sous titre
            FileUtils.rm_f("/tmp/Sub.srt") if File.exists?("/tmp/Sub.srt")
            
            if GetSub()
                # hack violent car j'ai jamais réussi à trouver comment definir un nouveau bouton dans l'interface
                # et le relier à la methode Vlc
                if ENV['USER'] == 'olivier'
                    system("/Applications/VLC.app/Contents/MacOS/VLC --sub-file /tmp/Sub.srt \"#{@prefs["Directories"]["Download"]+@current.fichier}\"")
                    else
                    @fenMovie.makeKeyAndOrderFront_(sender)
                    FileUtils.mv("/tmp/Sub.srt", @prefs["Directories"]["Download"]+@current.fichier+".srt")
                    @cinema.setMovie_(OSX::QTMovie.movieWithFile(@prefs["Directories"]["Download"]+@current.fichier))
                    @cinema.play(self)
                end
                else
                @fenMovie.close()
            end
        end
    end
    ib_action :Tester
    
    def Vlc(sender)
        if @current.candidats[@plusmoins.intValue-1].lien != ""
            # Récupération du sous titre
            if GetSub()
                FileUtils.mv("/tmp/Sub.srt", @prefs["Directories"]["Download"]+@current.fichier+".srt")
                system("/Applications/VLC.app/Contents/MacOS/VLC #{@prefs["Directories"]["Download"]+@current.fichier}")
            end
        end
    end
    ib_action :Vlc
    
    def TestOK(sender)
        
        @cinema.pause(self)
        
        if File.exist?(@prefs["Directories"]["Download"]+@current.fichier+".srt")
            # Créer l'arbo si nécessaire
            CheckArbo()
            
            # Déplacement du film
            ext = @current.fichier.split('.').last
            if (@prefs["Subs management"]["Move"] == 0)
                FileUtils.cp(@prefs["Directories"]["Download"]+@current.fichier, @current.repTarget+@current.fileTarget+".#{ext}")
                else
                FileUtils.mv(@prefs["Directories"]["Download"]+@current.fichier, @current.repTarget+@current.fileTarget+".#{ext}")
            end
            
            # Déplacement du sous titre
            FileUtils.mv(@prefs["Directories"]["Download"]+@current.fichier+".srt", @current.repTarget+@current.fileTarget+".srt")
            
            # Mise à jour du fichier de suivi
            updateHistory(sender)
            
            # Raffraichissement de la liste
            select_next_line
            @fenMovie.close()
        end
    end
    ib_action :TestOK
    
    def TestKO(sender)
        @cinema.pause(self)
        if File.exist?(@prefs["Directories"]["Download"]+@current.fichier+".srt")
            FileUtils.rm(@prefs["Directories"]["Download"]+@current.fichier+".srt")
        end
        @fenMovie.close()
    end
    ib_action :TestKO
    
    def GoWeb(sender)
        monURL = @current.candidats[@plusmoins.intValue-1].referer.to_s.strip
        return if monURL == ''
        system("open -a Safari '#{monURL}'")
    end
    ib_action :GoWeb
    
    def ViewSub(sender)
        if @current.candidats[@plusmoins.intValue-1].lien != ""
            if GetSub()
                system("open -a textedit /tmp/Sub.srt")
                else
                puts "Problem dans ViewSub"
            end
        end
    end
    ib_action :ViewSub
    
    def LoadSub(sender)
        if @current.candidats[@plusmoins.intValue-1].lien != ""
            if GetSub()
                FileUtils.mv("/tmp/Sub.srt", @prefs["Directories"]["Subtitles"]+@current.candidats[@plusmoins.intValue-1].fichier+".srt")
                else
                puts "Problem dans LoadSub"
            end
        end
    end
    ib_action :LoadSub
    
    def NoSub(sender)
        
        if (@current.repTarget == "") or (@current.fileTarget == "") then return end
        
        # Mettre à jour la liste
        @current.processed!
        
        # Rangement des fichiers
        CheckArbo()
        
        # Déplacement du film
        ext = @current.fichier.split('.').last
        if (@prefs["Subs management"]["Move"] == 0)
            FileUtils.cp(@prefs["Directories"]["Download"]+@current.fichier, @current.repTarget+@current.fileTarget+".#{ext}")
            else
            FileUtils.mv(@prefs["Directories"]["Download"]+@current.fichier, @current.repTarget+@current.fileTarget+".#{ext}")
        end
        
        # Mise à jour du fichier de suivi
        updateHistory(@bLoadSub)
        
        # Raffraichissement de la liste
        @current.comment = "Traité en Manuel"
        select_next_line
    end
    ib_action :NoSub
    
    def GetSub
        # Récupération du sous titre
        res = false
        if @current.candidats[@plusmoins.intValue-1].lien != ""
            begin
                plugin = Plugin.constantize(@current.candidats[@plusmoins.intValue-1].source)
                res = plugin.new(@current, @lignessources[plugin.index].rank, @plusmoins.intValue-1).retrieve_subtitle
                rescue NoMethodError => err
                $stderr.puts "# SubsMgr Error # GetSub [ #{@current.fichier} ] - #{err.inspect}"
            end
        end
        unless res
            select_next_line(true)
            return false
        end
        
        # Post Traitements
        if @bSupprCrochets.state == 1 then
            system('sed -e "s/\<[^\>]*\>//g" /tmp/Sub.srt > /tmp/Sub2.srt'); FileUtils.mv("/tmp/Sub2.srt", "/tmp/Sub.srt")
        end
        if @bSupprAccolades.state == 1 then
            system('sed -e "s/{[^}]*}//g" /tmp/Sub.srt > /tmp/Sub2.srt'); FileUtils.mv("/tmp/Sub2.srt", "/tmp/Sub.srt")
        end
        if @bCommande.state == 1 then
            system(@prefs["Subs management"]["Commande"])
        end
        
        return true
    end
    
    
    # ------------------------------------------
    # Fonctions liées aux répertoires et TVdb
    # ------------------------------------------
    def ViewDir(sender)
        if File.exist?(@current.repTarget)
            system("open -a Finder '"+@current.repTarget+"'")
        end
    end
    ib_action :ViewDir
    
    def SerieInfos(sender)
        
        @ovserie = @ligneslibrary[@listeseries.selectedRow()]
        @ovimage.setImage(@ovserie.image)
        
        # Remplissage du tableau et vérification du status
        @lignesinfos.clear()
        subsok = 0
        chargeok = 0
        for i in (0..@ovserie.nbepisodes-1)
            new_ligne = InfosSaison.new
            new_ligne.episode = @ovserie.episodes[i]["Episode"]
            new_ligne.titre = @ovserie.episodes[i]["Titre"]
            new_ligne.diffusion = @ovserie.episodes[i]["Diffusion"]
            new_ligne.telecharge = 0
            new_ligne.soustitre = 0
            
            temp1 = sprintf("s%02de%02d", @ovserie.saison, new_ligne.episode.to_i)
            temp2 = sprintf("%d%02d", @ovserie.saison, new_ligne.episode.to_i)
            temp3 = sprintf("%dx%02d", @ovserie.saison, new_ligne.episode.to_i)
            
            # Recherche de l'épisode
            for j in (0..@allEpisodes.size()-1)
                if @allEpisodes[j].fichier.downcase.match(@ovserie.serie.downcase) or @allEpisodes[j].fichier.downcase.match(@ovserie.serie.downcase.gsub(/ /, '.'))
                    if @allEpisodes[j].fichier.downcase.match(temp1) or @allEpisodes[j].fichier.downcase.match(temp2) or @allEpisodes[j].fichier.downcase.match(temp3)
                        new_ligne.telecharge = 1
                        chargeok = chargeok + 1
                        if @allEpisodes[j].status == "Traité"
                            new_ligne.soustitre = 1
                            subsok = subsok + 1
                        end
                    end
                end
            end
            
            @lignesinfos << new_ligne
        end
        
        # Calcul des stats
        temp = sprintf("Downloaded : %.1f %", chargeok*100/@lignesinfos.size())
        @ovcharge.setStringValue_(temp)
        temp = sprintf("Subtitled : %.1f %", subsok*100/@lignesinfos.size())
        @ovsubs.setStringValue_(temp)
        
        @ovliste.reloadData
        @fenInfos.makeKeyAndOrderFront_(sender)
        
    end
    ib_action :SerieInfos
    
    def SwitchView()
        taille = OSX::NSSize.new()
        
        if @vue.subviews[0].frame.width == 227.0
            while @vue.subviews[0].frame.width < 830.0
                taille.width = 832.0
                @vue.subviews[0].setFrameSize_(taille)
                @vue.displayIfNeeded
            end
            @bCleanSerie.setHidden(false)
            @bWebSerie.setHidden(false)
            manageButtons("Library")
            else
            while @vue.subviews[0].frame.width > 227.0
                taille.width = 227.0
                @vue.subviews[0].setFrameSize_(taille)
                @vue.displayIfNeeded
            end
            @bCleanSerie.setHidden(true)
            @bWebSerie.setHidden(true)
            manageButtons("Episodes")
        end
    end
    ib_action :SwitchView
    
    def GoWebSerie(sender)
        system("open -a Safari '"+@URLTVdb+"'")
    end
    ib_action :GoWebSerie
    
    def CleanSerie(sender)
    end
    ib_action :CleanSerie
    
    
    # ------------------------------------------
    # Fonctions de gestion des préférences
    # ------------------------------------------
    def Preferences (sender)
        @fenPref.makeKeyAndOrderFront_(sender)
    end
    ib_action :Preferences
    
    def PrefValid(sender)
        # Onglet Directories
        @prefs["Directories"]["Download"] = @pDirTorrent.stringValue()
        @prefs["Directories"]["Series"] = @pDirSerie.stringValue()
        @prefs["Directories"]["Banners"] = @pDirBanner.stringValue()
        @prefs["Directories"]["Subtitles"] = @pDirSubs.stringValue()
        @prefs["Directories"]["Torrents"] = @pDirTorrents.stringValue()
        
        # Onglet Naming Rules
        @prefs["Naming Rules"]["Directories"] = @pDirRule.selectedRow()
        @prefs["Naming Rules"]["Episodes"] = @pFileRule.selectedRow()
        @prefs["Naming Rules"]["Separator"] = @pSepRule.selectedColumn()
        
        # Onglet Automatism
        @prefs["Automatism"]["Min confidence"] = @pConfiance.selectedColumn()
        @prefs["Automatism"]["Schedule SearchAll"] = @pSchedSearch.indexOfSelectedItem()
        @prefs["Automatism"]["Schedule ProcessAll"] = @pSchedProcess.indexOfSelectedItem()
        @prefs["Automatism"]["Schedule RefreshAll"] = @pSchedRefresh.indexOfSelectedItem()
        @prefs["Automatism"]["Cache Depth"] = @pCacheDepth.indexOfSelectedItem()
        @prefs["Automatism"]["Forom key"] = @pForomKey.stringValue()
        
        # Onglet Sources
        @prefs["Sources"] ||= {}
        Plugin::LIST.each_with_index do |key, idx|
            @prefs["Sources"][key] ||= {}
            @prefs["Sources"][key]["Active"] = @lignessources[idx].active
            @prefs["Sources"][key]["Ranking"] = @lignessources[idx].rank
        end
        
        # Onglet Subs management
        @prefs["Subs management"]["Move"] = @pMove.selectedColumn()
        @prefs["Subs management"]["SupprCrochets"] = @pSupprCrochets.state()
        @prefs["Subs management"]["SupprAccolades"] = @pSupprAccolades.state()
        @prefs["Subs management"]["Commande"] = @pCommande.stringValue()
        
        
        @prefs.save_plist("#{Common::PREF_PATH}/SubsMgrPrefs.plist")
        PrefRefreshMain()
        
        # Activation des timers de refresh
        #case @prefs["Automatism"]["Schedule RefreshAll"]
        # when 0: if @TimerRefresh.isValid then @TimerRefresh.invalidate end
        # when 1: @TimerRefresh.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(15.0, self, :ScheduledRefresh, nil, true)
        # when 2: @TimerRefresh.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(60.0, self, :ScheduledRefresh, nil, true)
        #end
        
        @fenPref.close()
    end
    ib_action :PrefValid
    
    def PrefCancel(sender)
        # Lecture du plist
        @prefDefault = Plist::parse_xml(File.join(@appPath, "SubsMgrPrefs.plist"))
        @prefCurrent = Plist::parse_xml("#{Common::PREF_PATH}/SubsMgrPrefs.plist")
        @prefs = @prefDefault.deep_merge(@prefCurrent)
        
        # Onglet Directories
        @pDirTorrent.setStringValue(@prefs["Directories"]["Download"])
        @pDirSerie.setStringValue(@prefs["Directories"]["Series"])
        @pDirBanner.setStringValue(@prefs["Directories"]["Banners"])
        @pDirSubs.setStringValue(@prefs["Directories"]["Subtitles"])
        @pDirTorrents.setStringValue(@prefs["Directories"]["Torrents"])
        
        # Onglet Naming Rules
        @pDirRule.selectCellAtRow_column_(@prefs["Naming Rules"]["Directories"], 0)
        @pFileRule.selectCellAtRow_column_(@prefs["Naming Rules"]["Episodes"], 0)
        @pSepRule.selectCellAtRow_column_(0, @prefs["Naming Rules"]["Separator"])
        
        # Onglet Automatism
        @pConfiance.selectCellAtRow_column_(0, @prefs["Automatism"]["Min confidence"])
        @pSchedSearch.selectItemAtIndex(@prefs["Automatism"]["Schedule SearchAll"])
        @pSchedProcess.selectItemAtIndex(@prefs["Automatism"]["Schedule ProcessAll"])
        @pSchedRefresh.selectItemAtIndex(@prefs["Automatism"]["Schedule RefreshAll"])
        @pCacheDepth.selectItemAtIndex(@prefs["Automatism"]["Cache Depth"])
        @pForomKey.setStringValue(@prefs["Automatism"]["Forom key"])
        
        # Onglet Sources
        Plugin::LIST.each_with_index do |key, idx|
            if @prefs["Sources"][key]
                @lignessources[idx].active = @prefs["Sources"][key]["Active"]
                @lignessources[idx].rank = @prefs["Sources"][key]["Ranking"]
            end
        end
        
        # Onglet Subs management
        @pMove.selectCellAtRow_column_(0, @prefs["Subs management"]["Move"])
        @pSupprCrochets.setState(@prefs["Subs management"]["SupprCrochets"])
        @pSupprAccolades.setState(@prefs["Subs management"]["SupprAccolades"])
        @pCommande.setStringValue(@prefs["Subs management"]["Commande"])
        
        PrefRefreshMain()
        @fenPref.close()
        
        # Activation des timers de refresh
        #case @prefs["Automatism"]["Schedule RefreshAll"]
        # when 0: @TimerRefresh.invalidate()
        # when 1: @TimerRefresh.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(15.0, self, :ScheduledRefresh, nil, true)
        # when 2: @TimerRefresh.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(60.0, self, :ScheduledRefresh, nil, true)
        # end
        #@TimerRefresh = OSX::NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(60.0, self, :ScheduledRefresh, nil, true)
        #@TimerSearch = OSX::NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(5.0, self, :ScheduledSearch, nil, true)
        #@TimerProcess = OSX::NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(5.0, self, :ScheduledProcess, nil, true)
    end
    ib_action :PrefCancel
    
    def PrefRefreshMain()
        # maj plugins specifiques
        Plugin::Forom.forom_key = @pForomKey.stringValue().to_s
        Plugin::Local.local_path = @pDirSubs.stringValue().to_s
        
        # Affichage des sources actives dans la liste des épisodes
        # on prend en priorité les 3 sources les mieux rankées par l'utilisateur
        @sourcesActives = 0
        start = 3 # first source column
        @lignessources.find_all {|s|s.active == 1}.sort {|a, b| b.rank.to_f<=>a.rank.to_f}.each do |source|
            @sourcesActives += 1
            instance_variable_get("@source#{@sourcesActives}").setImage(source.image)
            idx = start + @sourcesActives - 1
            @liste.tableColumns[idx].setIdentifier(source.source)
            @liste.tableColumns[idx].setHeaderToolTip(source.source)
            
            # on ne dispose que de 3 colonnes de sources donc on arrête quand ca va deborder ;-)
            break if @sourcesActives == 3
        end
        
        # si moins de 3 sources, on complete l'initialisation
        while @sourcesActives < 3
            @sourcesActives += 1
            instance_variable_get("@source#{@sourcesActives}").setImage(Icones.list["None"])
            idx = start + @sourcesActives - 1
            @liste.tableColumns[idx].setIdentifier('None')
            @liste.tableColumns[idx].setHeaderToolTip('None')
        end
        
        @liste.reloadData()
        
        # Affichage des flags de Suppression des tags
        @bSupprCrochets.setState(@pSupprCrochets.state)
        @bSupprAccolades.setState(@pSupprAccolades.state)
        @pCommande.stringValue.blank? ? @bCommande.setState(0) : @bCommande.setState(1)
    end
    
    def PrefDirChoose(sender)
        panel = OSX::NSOpenPanel.alloc().init()
        panel.setCanChooseFiles_(false)
        panel.setCanChooseDirectories_(true)
        panel.setAllowsMultipleSelection_(false)
        
        if panel.runModal() == 1
            if (sender.description() == @pDirSubsButton.description())
                @pDirSubs.setStringValue(panel.filename()+"/")
            end
            if (sender.description() == @pDirSerieButton.description())
                @pDirSerie.setStringValue(panel.filename()+"/")
            end
            if (sender.description() == @pDirTorrentButton.description())
                @pDirTorrent.setStringValue(panel.filename()+"/")
            end
            if (sender.description() == @pDirBannerButton.description())
                @pDirBanner.setStringValue(panel.filename()+"/")
            end
            if (sender.description() == @pDirTorrentsButton.description())
                @pDirTorrents.setStringValue(panel.filename()+"/")
            end
        end
    end
    ib_action :PrefDirChoose
    
    def DeleteCache(sender)
        FileCache.clean()
    end
    ib_action :DeleteCache
    
end
