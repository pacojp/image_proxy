# -*- coding: utf-8 -*-

require './server'
use Rack::Reloader,3

# basically you should not use user_cache => true. because in front of this application, there should be proxy server like varnish.
run Server.new(:use_cache=>true)
#run Server.new
