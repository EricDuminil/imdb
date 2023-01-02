$LOAD_PATH.unshift(File.dirname(__FILE__)) unless
  $LOAD_PATH.include?(File.dirname(__FILE__)) || $LOAD_PATH.include?(File.expand_path(File.dirname(__FILE__)))

require 'open-uri'
require 'rubygems'
require 'nokogiri'

module Imdb
  # akas.imdb.com doesn't return original language anymore.
  # www.imdb.com returns 'Die Verurteilten' for 'The Shawshank Redemption' in Germany.
  # This header is needed to disable localizing.
  # use_it with open-uri's open or `curl`
  HTTP_HEADER = { 'Accept-Language' => 'en-US;en', 'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.95 Safari/537.36', "Referer" => "https://www.imdb.com/"}.freeze
  HTTP_PROTOCOL = 'https'.freeze
end

require 'imdb/util'
require 'imdb/base'
require 'imdb/movie'
require 'imdb/person'
require 'imdb/serie'
require 'imdb/season'
require 'imdb/episode'
require 'imdb/movie_list'
require 'imdb/search'
require 'imdb/top_250'
require 'imdb/box_office'
require 'imdb/string_extensions'
require 'imdb/version'
