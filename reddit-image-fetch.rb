#!/usr/bin/env ruby

DIRNAME = File.dirname(__FILE__)

require 'open-uri'
require 'sqlite3'
require 'json'
require 'pp'
require 'fileutils'
require 'net/http'
require 'nokogiri'
require 'colorize'

DB = SQLite3::Database.new(File.join(DIRNAME,"reddit.db"))

DB.execute("CREATE TABLE IF NOT EXISTS image
    (id text, subreddit text, link text, title text, permalink text, UNIQUE (id))")
DB.execute("CREATE TABLE IF NOT EXISTS handle_errors
    (error text, UNIQUE (error))")

def error(msg)
    STDERR.puts "Errror: #{msg}".colorize(:red)
end

HANDLES = {
    %r{jpg$}i       => "jpg",
    %r{imgur\.com}  => "imgur",
    %r{flickr\.com} => "flickr",
    %r{500px\.com} => "500px",
    %r{reddit\.com} => false
}

def handle_jpg(link, filename)
    `wget -q #{link} -O #{filename}`
end

def handle_imgur(link, filename)
    page = Nokogiri::HTML(open(link))

    begin
        link = "http:" + page.css("#image img")[0]["src"]
    rescue Exception => e
        error("**#{__method__}** " + e.message)
        return
    end

    handle_jpg(link, filename)
end

def handle_flickr(link, filename)
    prefix = %r{^.*flickr.com/photos/[^/]+/[^/]+}.match(link)[0]
    link = "#{prefix}/sizes/o/in/photostream/"

    page = Nokogiri::HTML(open(link))

    begin
        link = page.css("#allsizes-photo img")[0]["src"]
    rescue Exception => e
        error("**#{__method__}** " + e.message)
        return
    end

    handle_jpg(link, filename)
end

def handle_500px(link, filename)
    page = Nokogiri::HTML(open(link))

    begin
        link = page.css(".nude_placeholder img")[0]["src"]
    rescue Exception => e
        error("**#{__method__}** " + e.message)
        return
    end

    handle_jpg(link, filename)
end

def process(subr)
    url = "http://www.reddit.com/r/#{subr}/.json"

    begin
        page = JSON.parse(open(url).read)
    rescue
        error("Unable to read #{subr}")
        return
    end

    page["data"]["children"].each do |item|
        data  = item["data"]

        id        = data["id"]
        subreddit = data["subreddit"]
        link      = data["url"]
        title     = data["title"]
        permalink = data["permalink"]
        filename  = File.join DIRNAME, subreddit, "#{id}.jpg"

        rows = DB.execute('SELECT * FROM image WHERE id = ?',id)

        if rows.empty?
            begin
                DB.execute("INSERT INTO image VALUES (?,?,?,?,?)", id, subreddit, link, title, permalink)
            rescue Exception => e
                error(e.message)
            end
        end

        handle = nil
        HANDLES.each do |r,n|
            if r.match(link)
                if n
                    handle = "handle_#{n}"
                else
                    handle = n
                end

                break
            end
        end

        if handle.nil?
            error("No handle for #{link}")
            begin
                DB.execute("INSERT INTO handle_errors (error) VALUES (?)", link)
            rescue
            end

            next
        elsif handle == false
            puts "Skipping: #{title}".colorize(:yellow)
            next
        end

        FileUtils.mkdir_p(File.dirname(filename))

        if !File.exists?(filename)
            puts "Downloading: #{title}".colorize(:green)
            send(handle,link,filename)
        else
            puts "Skipping: #{title}".colorize(:yellow)
        end
    end
end

ARGV.each do |s|
    process(s)
end
