require 'tempfile'

module FileCache
  CACHE_PATH = "/tmp/subsmgr"

  module_function

  # recuperer un sous titre non compressé
  def get_srt(link, referer = nil)
    path = FileCache.get_srt(link, referer)
    FileUtils.cp(path, "/tmp/Sub.srt")
  end

  # recuperer un zip contenant le bon sous titre
  def get_zip(link, file, referer = nil)
    begin
      # Récupération du zip
      full_path = get_file(link, :refered => referer, :zip => true)

      # Extraction du zip
      if file == "None"
        # 1 seul fichier dans le zip
        system("/usr/bin/unzip -c -qq #{full_path} > /tmp/Sub.srt")
      else
        # Sélection du fichier dans le zip
        system("/usr/bin/unzip -c -qq #{full_path} '#{file}' > /tmp/Sub.srt")
      end
    rescue Exception => e
      $stderr.puts "# SubsMgr Error # get_zip [#{file}] : #{e.inspect}\n#{e.backtrace.join('\n')}"
      @current.comment = "Pb dans la récupération du zip"
    end
  end
  
  def recursive_unzip(zip_path)
    if `zipinfo -1 /tmp/test.zip |grep ".zip"|wc -l`.strip.to_i>0
      tmp = Tempfile.new("unzip")
      path = tmp.path
      File.unlink(path)
      system("mkdir -p #{path}; /usr/bin/unzip -j -o -qq #{zip_path} -d #{path}/; find #{path} -name \"*.zip\" -exec unzip -j -o {} -d #{path}/ \\; -exec rm {} \\; ; cd #{path}; zip -rj #{zip_path}.new .; mv #{zip_path}.new #{zip_path}")
      FileUtils.rm_rf(path)
    end
    zip_path
  end

  # recuperer un fichier quelconque
  # options:
  # :zip => true pour decompresser recursivement le zip si necessaire et retourne un zip "a plat"
  # :referer => url de referer a emuler
  # :path => chemin complet du stockage du fichier si c'est à conserver ailleurs (et dans ce cas, les repertoires doivent deja exister)
  def get_file(source, options = {})
    FileUtils.mkdir_p(CACHE_PATH)
    # on fabrique un nom de fichier unique pour le garder en cache pendant toute la journée
    crc = Digest::MD5.hexdigest("#{source}-#{Time.now.strftime('%Y-%m-%d')}")
    full_path = options[:path] || File.join(CACHE_PATH, crc)

    unless (File.exists?(full_path) && File.size(full_path)>0)
      file = BROWSER.get(source, :referer => options[:referer])
      File.open(full_path, "w") {|f| f.write(file.body)}
      recursive_unzip if options[:zip]
    end
    return full_path
  end

  def get_html(source, options = {})
    # options:
    # +referer+ : préciser un referer pour tromper d'eventuelle vérification sur le serveur
    # +xml+: ajouter :xml => true si la page demandée est une page XML
    FileUtils.mkdir_p(CACHE_PATH)
    # on fabrique un nom de fichier unique pour le garder en cache pendant toute la journée
    crc = Digest::MD5.hexdigest("#{source}-#{Time.now.strftime('%Y-%m-%d')}")
    full_path = File.join(CACHE_PATH, crc)

    if (File.exists?(full_path) && File.size(full_path)>0)
      if options[:xml]
        Nokogiri::HTML(open(full_path).read).root
      else
        Nokogiri::XML(open(full_path).read).root
      end
    else
      file = BROWSER.get(source, :referer => options[:refered])
      File.open(full_path, "w") {|f| f.write(file.body.to_s)}
      if options[:xml]
        file = Nokogiri::XML(file.body).root
      else
        file.root
      end
    end
  end

end
