#!/usr/bin/env ruby

require 'open-uri'
require 'sqlite3'
require 'json'
require 'pp'
require 'fileutils'
require 'net/http'

DB = SQLite3::Database.new("reddit.db")
DB.execute("CREATE TABLE IF NOT EXISTS image
    (id text, subreddit text, link text, title text, permalink text, UNIQUE (id))")

def error(msg)
    STDERR.puts("Errror: #{msg}")
end

def handle_jpg(link, filename)
    `wget -q #{link} -O #{filename}`
end

HANDLES = {
    /jpg$/i => "jpg"
}

subr = "earthporn"

url = "http://www.reddit.com/r/#{subr}/.rss"
url = "#{subr}.json"

page = JSON.parse(File.read(url))

page["data"]["children"].each do |item|
    data  = item["data"]

    id        = data["id"]
    subreddit = data["subreddit"]
    link      = data["url"]
    title     = data["title"]
    permalink = data["permalink"]
    filename  = File.join subreddit, "#{id}.jpg"

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
            handle = "handle_#{n}"
            break
        end
    end

    if handle.nil?
        error("No handle for #{link}")
        next
    end

    FileUtils.mkdir_p(subreddit)

    if !File.exists?(filename)
        puts "Downloading: #{title}"
        send(handle,link,filename)
    else
        puts "Skipping: #{title}"
    end
end
