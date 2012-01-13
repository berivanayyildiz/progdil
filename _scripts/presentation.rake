# Gerekli Kütüphaneleri içerde çalýþtýr.
require 'pathname'
require 'pythonconfig'
require 'yaml'

# presentation bilgileri ni al yoksa boþ kullan
CONFIG = Config.fetch('presentation', {})

# directoryi al yoksa "p"yi al
PRESENTATION_DIR = CONFIG.fetch('directory', 'p')
# conffileyi al yoksa "_templates/presentation.cfg"yia al
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg')
# "p" dizinindeki index.html'ye gir
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html')
# En büyük Resimebatý 733,550
IMAGE_GEOMETRY = [ 733, 550 ]
# baðýmlýlýklarý css ve js olarak taný
DEPEND_KEYS = %w(source css js)
DEPEND_ALWAYS = %w(media) # liste = ['media']

# tanimlamalar yapýlýyor
TASKS = {
    :index => 'sunumlarý indeksle',
    :build => 'sunumlarý oluþtur',
    :clean => 'sunumlarý temizle',
    :view => 'sunumlarý görüntüle',
    :run => 'sunumlarý sun',
    :optim => 'resimleri iyileþtir',
    :default => 'öntanýmlý görev',
}

# Sunum sözlüðü
presentation = {}
# Tag sözlüðü
tag = {}

class File
  #Pathname.pwd'yi absolute_path_here deðiþkenine ata
  @@absolute_path_here = Pathname.new(Pathname.pwd)
  # absolute_path_here deðiþkenine göre yeni path oluþtur
  def self.to_herepath(path)
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end

  # path'teki dosyalari listele
  def self.to_filelist(path)
  # o path'deki tüm dosya/dizinlerden dosya olanlarý al 
    File.directory?(path)
      FileList[File.join(path, '*')].select { |f| File.file?(f) }
# [path] olarak döngüye geri dön  
   [path]
  end
end


def png_comment(file, string)
# Gerekli Kütüphaneleri içerde çalýþtýr.
  require 'chunky_png'
  require 'oily_png'

# resimleri al ve kaydet
  image = ChunkyPNG::Image.from_file(file)
  image.metadata['Comment'] = 'raked'
  image.save(file) 
end

# png dosyalarýný düzenle ve boyutlandýr.
def png_optim(file, threshold=40000)
  # boyut threshold=40000 den küçük ise geri dön
  return if File.new(file).size < threshold
  # resmin boyutunu küçültürek optimize et
  sh "pngnq -f -e .png-nq #{file}"
  out = "#{file}-nq"
# eðer çýkýlmýþsa resmi sil
  if File.exist?(out)
    $?.success? ? File.rename(out, file) : File.delete(out)
  end
  # Resim iþlendi
  png_comment(file, 'raked')
end

# jpg dosyalarýný düzenle.
def jpg_optim(file)
  sh "jpegoptim -q -m80 #{file}"
  sh "mogrify -comment 'raked' #{file}"
end

def optim

  # png ve jpg dosyalarýný listele
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"]

# düzenlenen resimleri listele ve döngüye iþle.
  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }
  end

   # Boyutlar düznelenir
  (pngs + jpgs).each do |f|
    # geniþlik w yukseklik h olarak tanýla
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i }
  # boyutlarý size deðiþkenine tanýmla
    size, i = [w, h].each_with_index.max
      # Eðer size tanýmlanan boyut 733,550 den buyukse yeniden boyutlandýr
    if size > IMAGE_GEOMETRY[i]
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s
      sh "mogrify -resize #{arg} #{f}" 
    end
  end

  # png ve jp dosyalarý düzenlendi.
  pngs.each { |f| png_optim(f) }
  jpgs.each { |f| jpg_optim(f) }

  # pngs ve jpgs dosyalarýný al md uzantýlý dosyalarla karsýlastýrç olamayanlarý oluþtur.
  (pngs + jpgs).each do |f|
    name = File.basename f
    FileList["*/*.md"].each do |src|
      sh "grep -q '(.*#{name})' #{src} && touch #{src}"
    end
  end
end

# default_conffile tam yolunu al
default_conffile = File.expand_path(DEFAULT_CONFFILE)

# "_" ile baþlamayan tüm doslayalarý al ve bunlarda gez
FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir|
  next unless File.directory?(dir)
  chdir dir do
    name = File.basename(dir)
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile
    config = File.open(conffile, "r") do |f| # Dosyayý aç
      PythonConfig::ConfigParser.new(f)
    end
    # lanslide deðiþkenini tanýmla
    landslide = config['landslide']


# landslide yoksa hata mesajý çýkar ve çýk
    if ! landslide 
      $stderr.puts "#{dir}: 'landslide' bölümü tanýmlanmamýþ"
      exit 1
    end
# landslide'ta 'destination' ayarý kullanýlmýþ ise hata ver ve çýk
    if landslide['destination'] 
      $stderr.puts "#{dir}: 'destination' ayarý kullanýlmýþ; hedef dosya belirtilmeyin"
      exit 1
    end
    # index.md varsa base'yi index olarak tanýmla ve ispublic'ði doðru olarak tanýmla
    if File.exists?('index.md')
      base = 'index'
      ispublic = true

    # index.md deðilse presentation.md varsasa base'yi presentation olarak tanýmla ve ispublic'ði yanlýþ olarak tanýmla
    elsif File.exists?('presentation.md')
      base = 'presentation'
      ispublic = false

    # index.md ve presentation.md yoksa hatave veçýk
    else
      $stderr.puts "#{dir}: sunum kaynaðý 'presentation.md' veya 'index.md' olmalý"
      exit 1
    end

    # md dosyalarýný html olarak tanýmla
    basename = base + '.html'
    # thumbnail'i resmin tam yolu olarak tanýmla
    thumbnail = File.to_herepath(base + '.png') )
    # target'i html(index,presentation) dosyasýnýn tam yolu olarak tanýmla
    target = File.to_herepath(basename)


    deps = []
 
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
    end


    # html(target) ve png(thumbnail) dosyalarýný sil
    deps.map! { |e| File.to_herepath(e) }
    deps.delete(target)
    deps.delete(thumbnail)

    tags = [] 

   # Sunum dizini ile ilgili bilgileri persentation' da tanýmla
   presentation[dir] = {
      :basename => basename, # üreteceðimiz sunum dosyasýnýn baz adý
      :conffile => conffile, # landslide konfigürasyonu (mutlak dosya yolu)
      :deps => deps, # sunum baðýmlýlýklarý
      :directory => dir, # sunum dizini (tepe dizine göreli)
      :name => name, # sunum ismi
      :public => ispublic, # sunum dýþarý açýk mý
      :tags => tags, # sunum etiketleri
      :target => target, # üreteceðimiz sunum dosyasý (tepe dizine göreli) # html yani
      :thumbnail => thumbnail, # sunum için küçük resim # png yani
    }
  end
end


presentation.each do |k, v|
  v[:tags].each do |t|
    tag[t] ||= [] # Eðer ki tag boþ ise
    tag[t] << k # Boþ tagý doldur
  end
end

# görev tablosu oluþtur 
tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten]

# presentation 'da dön
presentation.each do |presentation, data| 
# ns yi yeni isimde tanýmla
  ns = namespace presentation do 
 # html dosyasýný al
    file data[:target] => data[:deps] do |t|
# presentation  dizine gir
      chdir presentation do
        sh "landslide -i #{data[:conffile]}"
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
# data[:basename] adi presentation.html deðilse
        unless data[:basename] == 'presentation.html'
#data[:basename] altýna presentation.html'i getir
          mv 'presentation.html', data[:basename]
        end
      end
    end


    file data[:thumbnail] => data[:target] do
      next unless data[:public] 
#ekran görüntüsü al
      sh "cutycapt " + 
#resmi al
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " + 
 #dýþa aktar
          "--out=#{data[:thumbnail]} " +
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " +
# minimum geniþlik 1024px
          "--min-width=1024 " + 
# minumum yükseklik 768px
          "--min-height=768 " + 
# sunumlar arasý  geçiþ 1000(ms) olsun
          "--delay=1000" 
# dosya yeniden boyutlandýrýlýr
      sh "mogrify -resize 240 #{data[:thumbnail]}"
#düzenlenen dosya data[:thumbnail] ekaydedilir
      png_optim(data[:thumbnail])
    end

# optimize yapar (düzenleme) presentation dizininde
    task :optim do 
      chdir presentation do
        optim
      end
    end

    task :index => data[:thumbnail] 
    task :build => [:optim, data[:target], :index]


    task :view do
# data[:target]  varmi diye bakar
      if File.exists?(data[:target])
# varsa dizini oluþtur
        sh "touch #{data[:directory]}; #{browse_command data[:target]}"
#yoksa hata ver ve çýk
      else
        $stderr.puts "#{data[:target]} bulunamadý; önce inþa edin"
      end
    end

    task :run => [:build, :view] 
# html ve png leri siliyoruz
    task :clean do
      rm_f data[:target]
      rm_f data[:thumbnail] 
    end

    task :default => :build 

  end
  
# "tasktab"a "ns"nin "map"lenmiþ halini kaydet.
  ns.tasks.map(&:to_s).each do |t|
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name]
    tasktab[name][:tasks] << t
  end
end

# p uzayýnda görevleri göster
namespace :p do
  tasktab.each do |name, info|
    desc info[:desc] 
    task name => info[:tasks]
    task name[0] => name
  end

  task :build do 
# indexfile varsa yukle yoksa boþ al
    index = YAML.load_file(INDEX_FILE) || {}
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort
    unless index and presentations == index['presentations']
      index['presentations'] = presentations
      File.open(INDEX_FILE, 'w') do |f|
        f.write(index.to_yaml)
        f.write("---\n")
      end
    end
  end
  desc "sunum menüsü"
 # Sunum oluþturup sunumu seç ve göster
  task :menu do
    lookup = Hash[
      *presentation.sort_by do |k, v|
        File.mtime(v[:directory])
      end
      .reverse
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
    name = choose do |menu|
# 1. sunum ilk sunum olsun
      menu.default = "1" 
      menu.prompt = color(
        'Lütfen sunum seçin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]
    Rake::Task["#{directory}:run"].invoke
  end
# menu yerine m de kullanýlýr
  task :m => :menu 
end
# p:menu ile sunum çalýþtýrýlýr.
desc "sunum menüsü"
task :p => ["p:menu"] 
task :presentation => :p
