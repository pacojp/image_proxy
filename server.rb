# -*- coding: utf-8 -*-

require 'rack'
require 'uri'
require 'open-uri'
require 'singleton'

require 'filecache'
require 'imlib2'

class Conf
  include Singleton

  attr_accessor :use_cache,:home,:tmp_folder,:error_image

  def load(options)
    @use_cache = false
    if options[:use_cache]
      @use_cache = options[:use_cache]
    end
    @home = File.expand_path(File.dirname(__FILE__)) + '/'
    @tmp_folder = @home + 'tmp/'
    File.open(@home + '/dat/error.jpg', "rb") {|f| @error_image = f.read }
  end
end

class Server

  attr_accessor :cache

  def initialize(options={})
    Conf.instance.load(options)
    if Conf.instance.use_cache
      cache_home = Conf.instance.home + 'cache/'
      @cache = FileCache.new("images", cache_home, 60 * 60 * 24 * 7, 6)
    end
  end

  #
  # TODO
  #
  def call(env)
    uri = env["REQUEST_URI"]
    url = uri.clone
    #puts url
    url = $1 if url =~ /^\/(.*+)$/
    options = []

    if url =~ /^([^\/]+?)\/(http:\/\/.*)$/
      url = $2
      options = $1.gsub(/%7c/i,'|').split('|')
    end

    #puts "url=#{url}"
    #puts "env[\"REQUEST_URI\"]=#{env["REQUEST_URI"]}"

    if url =~ /^(.*?)\/conv2\.(jpe?g|gif|png)$/i
      url = $1
      format = $2.downcase
      format = "jpg" if format == "jpeg"
      options << "convert_to:#{format}"
    end

    case url
    when "favicon.ico"
      [404, {"Content-Type" => "text/plain"}, ['']]
    when /^http:\/\//
      begin
        if @cache
          hash = Digest::MD5.hexdigest(uri)
          unless img = @cache.get(hash)
            #puts "cache not hit"
            img = get_data(url,options)
            @cache.set(hash,img)
          end
        else
          img = get_data(url,options)
        end
        #puts "response=#{img.content_type}"
        [200, {"Content-Type" => img.content_type}, [img.data]]
      rescue => e
        #puts e.message
        [500, {"Content-Type" => "text/plain"}, ["process error(#{e.message})"+e.backtrace.join("\n")]]
      end
    else
      [404, {"Content-Type" => "text/plain"}, ['request_uri format must be http://~']]
    end
  end

  def get_data(url,options)
    img = Image.new(url,options)
    img.process!
    return img
  end
end

class Image
  attr_accessor :content_type,:ori_data,:url,:options,:data

  def initialize(url,options)
    @url = url
    @options=options
  end

  def process!
    begin
      self.load_inner
      self.convert_inner
    rescue => e
      puts e.message
      self.data = Conf.instance.error_image
      self.content_type = "image/jpeg"
    end
  end

  protected

  def load_inner
    data = open(@url).read
    raise 'data null' unless data
    raise 'data size error ' if data.size < 1
    self.ori_data = data
    nil
  end

  def convert_inner
    tf = Tempfile.new('image',Conf.instance.tmp_folder)
    path = tf.path
    tf.write(self.ori_data)
    tf.close

    new_path = path + "img.jpg"
    
    if path =~ /.gif$/i
      `/usr/bin/imlib2_conv #{path} #{new_path}`
      img = Imlib2::Image.load(new_path)
    else
      img = Imlib2::Image.load(path)
    end

    options.each do |opt|
      case opt
      when /^(\d+)x(\d+)$/
        resize(img,$1,$2)
      end
    end
    img.save(new_path)

    self.data = File.open(new_path).read
    self.content_type = "image/jpeg"
    File.unlink(new_path)
    nil
  end

  def resize(img,new_w,new_h)
    new_w = Integer(new_w)
    new_h = Integer(new_h)
    if new_w >= img.w && new_h >= img.h
      # do not resize
      return
    else
      if img.w > new_w && new_h >= img.h
        # adjust by width
      end

      if img.h > new_h && new_w >= img.w
        # adjust by height
        new_w = ((new_h.to_f/img.h)*img.w).round
      end

      if ((new_w.to_f / img.w.to_f) * img.h.to_f ) > new_h
        # adjust by height
        new_w = ((new_h.to_f/img.h)*img.w).round
      else
        # adjust by width
        new_h = ((new_w.to_f / img.w) * img.h).round
      end
      img.crop_scaled!(0, 0, img.w, img.h, new_w, new_h)
    end
  end
end

