module Imdb
  # Represents something on IMDB.com
  class Base
    include Util

    attr_accessor :id, :url, :related_person, :related_person_role
    attr_writer :title, :year, :poster_thumbnail

    BIG_TEXT = 'name-credits--title-text-big'

    # Initialize a new IMDB movie object with it's IMDB id (as a String)
    #
    #   movie = Imdb::Movie.new("0095016")
    #
    # Imdb::Movie objects are lazy loading, meaning that no HTTP request
    # will be performed when a new object is created. Only when you use an
    # accessor that needs the remote data, a HTTP request is made (once).
    #
    def initialize(imdb_id, title = nil)
      @id = imdb_id
      @url = Imdb::Base.url_for(@id, :reference)
      @title = title.delete('"').strip if title
    end

    def reload
      @title = nil
      @year = nil
      @poster_thumbnail = nil
    end

    # Returns an array with cast members
    def cast_members
      get_nodes("//div[@data-testid='sub-section-cast']//li[@data-testid='name-credits-list-item']//a[contains(@class, '#{BIG_TEXT}')]")
    end

    def cast_member_ids
      get_nodes("//div[@data-testid='sub-section-cast']//li[@data-testid='name-credits-list-item']//a[contains(@class, '#{BIG_TEXT}')]") { |a| a['href'][/(?<=\/name\/)nm\d+/] }
    end

    # Returns an array with cast characters
    def cast_characters
      get_nodes("//div[@data-testid='sub-section-cast']//li[@data-testid='name-credits-list-item']//a[contains(@class, 'ipc-link--inherit-color')]")
    end

    # Returns an array with cast members and characters
    def cast_members_characters(sep = '=>')
      cast_members.zip(cast_characters).map do |cast_member, cast_character|
        "#{cast_member} #{sep} #{cast_character}"
      end
    end

    # FIXME
    # Returns an array of starring actors as strings
    def starring_actors
      get_nodes("//div[h4[text()='Stars:']]/a[starts-with(@href, '/name/')]", apex_document)
    end

    # Returns the name of the directors.
    # Extracts from full_credits for movies with more than 3 directors.
    def directors
      # top_directors = get_nodes("//span[starts-with(text(), 'Director')]/ancestor::section[1]//a")
      top_directors = get_nodes("//div[@data-testid='sub-section-director']//a[contains(@class, '#{BIG_TEXT}')]")
      if top_directors.empty? || top_directors.last.start_with?('See more')
        all_directors
      else
        top_directors
      end
    end

    # NOTE: Keeping Base#director method for compatibility.
    alias director directors

    # Returns the names of Writers
    # Extracts from full_credits for movies with more than 3 writers.
    def writers
      top_writers = get_nodes("//div[@data-testid='sub-section-writer']//a[contains(@class, '#{BIG_TEXT}')]")
      if top_writers.empty? || top_writers.last.start_with?('See more')
        all_writers
      else
        top_writers
      end
    end

    # Returns the url to the "Watch a trailer" page
    def trailer_url
      get_node("a[@href^='videoplayer/']") do |trailer_link|
        "#{Imdb::HTTP_PROTOCOL}://www.imdb.com/" + trailer_link['href']
      end
    end

    # Returns an array of genres (as strings)
    def genres
      get_nodes("//li[span[starts-with(text(), 'Genre')]]/div/ul/li/a")
    end

    # Returns an array of languages as strings.
    def languages
      get_nodes("//li[span[starts-with(text(), 'Language')]]/div/ul/li/a")
    end

    # Returns an array of countries as strings.
    def countries
      get_nodes("//li[span[starts-with(text(), 'Countr')]]/div/ul/li/a")
    end

    # Returns the duration of the movie in minutes as an integer.
    def length
      get_node("//li[span[text()='Runtime']]/div/ul/li/span[contains(text(), 'min')]") do |runtime|
        runtime.content[/(\d+) min/].to_i
      end
    end

    # Returns a single production company (legacy)
    def company
      production_companies.first
    end

    # Returns a list of production companies
    def production_companies
      get_nodes("//h4[text()='Production Companies']/following::ul[1]/li/a[contains(@href, '/company/')]")
    end

    # Returns a string containing the (possibly truncated) plot summary.
    def plot
      get_node('//section[contains(@class, "overview")]//hr[last()]/preceding-sibling::div[1]') do |plot_html|
        sanitize_plot(plot_html.content.strip)
      end
    end

    # Returns a string containing the plot synopsis
    def plot_synopsis
      get_node("li[@id*='synopsis']", summary_document)
    end

    # Retruns a string with a longer plot summary
    def plot_summary
      get_node("//tr[td[contains(@class, 'label') and text()='Plot Summary']]/td[2]/p/text()")
    end

    # Returns a string containing the URL for a thumbnail sized movie poster.
    def poster_thumbnail
      @poster_thumbnail || get_node("img[@alt*='Poster']") { |poster_img| poster_img['src'] }
    end

    # Returns a string containing the URL to the movie poster.
    def poster
      case poster_thumbnail
      when /^(https?:.+@@)/
        Regexp.last_match[1] + '.jpg'
      when /^(https?:.+?)\.[^\/]+$/
        Regexp.last_match[1] + '.jpg'
      end
    end

    # Returns a float containing the average user rating
    def rating
      get_node('.ipl-rating-star__rating') do |rating_html|
        rating_html.content.strip.to_f
      end
    end

    # Returns an enumerator of user reviews as hashes
    # NOTE: Not an enumerator of arrays of hashes anymore.
    def user_reviews
      Enumerator.new do |enum|
        data_key = nil
        loop do
          reviews_doc = userreviews_document(data_key)
          review_divs = reviews_doc.search('div.review-container')
          break if review_divs.empty?
          review_divs.each do |review_div|
            title = review_div.at('div.title').text
            text = review_div.at('div.content div.text').text
            rating_html = review_div.at_xpath(".//span[@class='point-scale']/preceding-sibling::span")
            rating = rating_html.text.to_i if rating_html
            enum.yield(title: title, review: text, rating: rating)
          end
          # Extracts the key for the next page
          more_data_html = reviews_doc.at('div.load-more-data')
          if more_data_html
            data_key = more_data_html['data-key']
          else
            break
          end
          sleep 1
        end
      end
    end

    # Returns an int containing the Metascore
    def metascore
      get_node('div[@class*="metacriticScore"]/span', apex_document) do |metascore_html|
        metascore_html.content.to_i
      end
    end

    # Returns an int containing the number of user ratings
    def votes
      get_node('.ipl-rating-star__total-votes') do |votes_html|
        votes_html.content.strip.gsub(/[^\d+]/, '').to_i
      end
    end

    # Returns a string containing the tagline
    def tagline
      get_node("//tr[td[contains(@class, 'label') and text()='Taglines']]/td[2]/text()")
    end

    # Returns a string containing the mpaa rating and reason for rating
    def mpaa_rating
      get_node("span[@itemprop='contentRating']", apex_document)
    end

    # Returns a string containing the MPAA letter rating.
    # IMDB Certificates also include 'TV-14' or 'TV-MA', so they need to be filtered out.
    def mpaa_letter_rating
      document.search("a[@href*='certificates=US%3A']").map do |a|
        a.text.gsub(/^United States:/, '')
      end.find { |r| r =~ /\b(G|PG|PG-13|R|NC-17)\b/ }
    end

    # Returns a string containing the original title if present, the title otherwise.
    # Even with localization disabled, "Die Hard" will be displayed as "Stirb langsam (1998) Die Hard (original title)" in Germany
    def title(force_refresh = false)
      if @title && !force_refresh
        @title
      else
        # Title format has been changed in june 2025
        original_title = get_node('//h1/following-sibling::div[1]/text()')
        @title = if original_title.nil?
            get_node('//span[@class="hero__primary-text"]/text()')
          else
            original_title.sub(/Original title: ?/i, '')
          end
      end
    end

    # Returns an integer containing the year (CCYY) the movie was released in.
    def year
      @year || get_node("//h3[@itemprop='name']/span/a/text()") { |year_html| year_html.content.strip.to_i }
    end

    # Returns release date for the movie.
    def release_date
      get_node("div.titlereference-header a[@href*='/releaseinfo']") do |date_html|
        sanitize_release_date(date_html.text)
      end
    end

    # Returns filming locations from imdb_url/locations
    def filming_locations
      get_nodes('#filming_locations .soda dt a', locations_document)
    end

    # Returns alternative titles from imdb_url/releaseinfo
    def also_known_as
      get_nodes('#akas tr', releaseinfo_document) do |aka|
        {
          version: aka.at('td:nth-child(1)').text,
          title: aka.at('td:nth-child(2)').text,
        }
      end
    end

    private

    # Returns a new Nokogiri document for parsing.
    def document
      @document ||= Nokogiri::HTML(Imdb::Movie.find_by_id(@id))
    end

    def locations_document
      @locations_document ||= Nokogiri::HTML(Imdb::Movie.find_by_id(@id, 'locations'))
    end

    def releaseinfo_document
      @releaseinfo_document ||= Nokogiri::HTML(Imdb::Movie.find_by_id(@id, 'releaseinfo'))
    end

    def fullcredits_document
      @fullcredits_document ||= Nokogiri::HTML(Imdb::Movie.find_by_id(@id, 'fullcredits/?ref_=tt_cst_sm'))
    end

    def apex_document
      @apex_document ||= Nokogiri::HTML(Imdb::Movie.find_by_id(@id, ''))
    end

    def summary_document
      @summary_document ||= Nokogiri::HTML(Imdb::Movie.find_by_id(@id, 'plotsummary'))
    end

    def userreviews_document(data_key = nil)
      path = if data_key
          "reviews/_ajax?paginationKey=#{data_key}"
        else
          'reviews'
        end
      Nokogiri::HTML(Imdb::Movie.find_by_id(@id, path))
    end

    def all_directors
      query = "//div[@data-testid='sub-section-director']//a[contains(@class, '#{BIG_TEXT}')]"
      get_nodes(query, fullcredits_document)
    end

    def all_writers
      query = "//div[@data-testid='sub-section-writer']//a[contains(@class, '#{BIG_TEXT}')]"
      get_nodes(query, fullcredits_document)
    end

    def self.find_by_id(imdb_id, page = :reference)
      URI.open(p(Imdb::Base.url_for(imdb_id, page)), Imdb::HTTP_HEADER)
    end

    def self.url_for(imdb_id, page = :reference)
      "#{Imdb::HTTP_PROTOCOL}://www.imdb.com/title/tt#{imdb_id.to_s.rjust(7, '0')}/#{page}"
    end

    # Convenience method for search
    def self.search(query)
      Imdb::Search.new(query).movies
    end

    def self.top_250
      Imdb::Top250.new.movies
    end

    def sanitize_plot(the_plot)
      the_plot = the_plot.gsub(/add\ssummary|full\ssummary/i, '')
      the_plot = the_plot.gsub(/add\ssynopsis|full\ssynopsis/i, '')
      the_plot = the_plot.gsub(/see|more|\u00BB|\u00A0/i, '')
      the_plot = the_plot.gsub(/\|/i, '')
      the_plot.strip
    end

    def sanitize_release_date(the_release_date)
      the_release_date.gsub(/see|more|\u00BB|\u00A0/i, '').strip
    end
  end # Movie
end # Imdb
