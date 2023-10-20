require "rubygems"
require "sinatra"
require "net/http"
require "uri"
require "haml"
require "time"
require "sequel"
require "logger"

DATE_FORMAT = "%Y-%m-%d"
next_friday = Time.now + (5 - Time.now.wday) * 24 * 60 * 60
next_friday = next_friday.strftime(DATE_FORMAT)

HN_URI = "https://www.regmovies.com/us/data-api-service/v1/quickbook/10110/film-events/in-cinema/0354/at-date/#{next_friday}?attr=&lang=en_US"

# 02 Oct 2002 15:00:00 +0200
TIME_FORMAT = "%d %b %Y %H:%M:%S %z"  

SELF_URI = "http://api.kanna.in/hnbest"

UPDATE_INTERVAL = 600

#####################
### DATABASE PART ###
#####################

DB = Sequel.connect(ENV['DATABASE_URL'] || "sqlite:///tmp/regal.db")
DB.loggers << Logger.new($stdout)
DB.create_table? :items do
  primary_key :id
  String :url, :null => false
  String :name, :null => false
  Integer :length, :null => false
  DateTime :post_time, :null => false
end
DB.create_table? :last_update do
  primary_key :id
  DateTime :last_update, :null => false
end

def update_database
  uri = URI.parse(HN_URI)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  response = http.request(Net::HTTP::Get.new(uri.request_uri)).body
  response = JSON.parse(response)

  items = DB[:items]
  response["body"]["films"].each do |film|
    item = {}
    item[:link] = film["link"]
    item[:url] = film["link"]
    item[:name] = film["name"]
    item[:length] = film["length"]
    item[:post_time] = Time.now
    items.insert(item)
  end
  
  killtime = Time.now - UPDATE_INTERVAL
  items.filter{post_time < killtime}.delete
  
  last_update = DB[:last_update]
  last_update.delete
  last_update.insert(:last_update => Time.now)
  
  nil
end

def last_update
  lu = DB[:last_update].select(:last_update).all.first
  if lu
    lu[:last_update]
  else
    Time.now - 2 * UPDATE_INTERVAL
  end
end

def fetch_items(count)
  if last_update < Time.now - UPDATE_INTERVAL
    update_database
  end
  
  DB.from(DB[:items].limit(count).as(:posts)).order(Sequel.desc(:post_time)).all
end

####################
### SINATRA PART ###
####################

configure do
  mime_type :rss, "application/rss+xml"
end

get "/" do
  haml :index, :escape_html => true
end

get "/regal" do
  if params[:count]
    item_count = params[:count].to_i
  else
    item_count = 30
  end
  if item_count <= 0
    item_count = 30
  end

  content_type :rss
  items = fetch_items item_count
  lu = last_update
  haml :rss, :escape_html => true,
       :locals => {:link => 'https://www.regmovies.com/',
                   :items => items,
                   :self_href => SELF_URI,
                   :last_build => lu,
                   :time_format => TIME_FORMAT,
                   :link_comments => params[:link_comments].to_i == 1}
end

#################
### HAML PART ###
#################
__END__
@@ index
!!! 5
%html
  %head
    %title Regal Movies RSS
    %meta{:name => "keywords",
          :content => "regal, movies, rss, best"}
    %link{:rel => "alternate",
          :type => "application/rss+xml",
          :title => "Regal Movies RSS",
          :href => "/rss"}
  %body
    %h1
      Regal Movies RSS
      %a{:href => "/rss"} RSS
    %p
      You can append the GET-parameter "count=n" to reduce the amount of news items to n. The default is 30.
    %p
      You can append the GET-parameter "link_comments=1" to make the RSS entries point to the discussion instead of the submitted content. The default is to link to the submitted URL.
    %p
      %a{:href => "https://github.com/vrajeshkanna/hnbest"} Github
@@ rss
!!! XML
%rss{:version => "2.0", "xmlns:atom" => "http://www.w3.org/2005/Atom"}
  %channel
    %title Regal Movies
    %link= link
    <atom:link href="#{self_href}" rel="self" type="application/rss+xml" />
    %description This feed contains Regal new movie entries.
    %lastBuildDate= last_build.strftime(time_format)
    %language en
    -items.each do |item|
      %item
        %title= item[:name]
        %link= item[:url]
        %guid= item[:url]
        %pubDate= item[:post_time].strftime(time_format)
        %description
          <![CDATA[
          %p
            %a{:href => item[:url]}= item[:title]
          ]]>
      

