require 'sinatra'
require 'nt_models'
require 'activerecord-import'
require 'redis'
require 'open-uri'

set :port, 9494 unless Sinatra::Base.production?

unless Sinatra::Base.production?
  # load local environment variables
  require 'dotenv'
  Dotenv.load 'config/local_vars.env'
end

# Comment this out when using a local Redis instancs
configure do
  uri = URI.parse(ENV['REDISTOGO_URL'])
  REDIS = Redis.new(host: uri.host, port: uri.port, password: uri.password)
end
# REDIS = Redis.new # Uncomment this when using a local Redis instance

# Adds new Tweet to Follower's Redis timeline cache
def cache_tweet(follower_id, tweet)
  timeline_size = REDIS.incr("#{follower_id}:timeline_size") # Update timeline size
  REDIS.hmset(                                              # Insert new Tweet
    "#{follower_id}:#{timeline_size}",
    'id', tweet.id,
    'body', tweet.body,
    'created_on', tweet.created_on,
    'author_handle', tweet.author_handle
  )
end

post '/new_tweet/:id' do
  t = Tweet.find(params[:id])
  author = t.author
  mapped = author.follows_to_me.map do |f|
    cache_tweet(f.follower_id, t)
    [f.follower_id, t.id, t.body, t.created_on, t.author_handle]
  end
  import_timeline_pieces(mapped)
  status 200
end

post '/new_follower/:followee_id/:follower_id' do
  followee_tweets = Tweet.where(author_id: params[:followee_id])
  follower_id = params[:follower_id]
  mapped = followee_tweets.map do |t|
    cache_tweet(follower_id, t)
    [follower_id, t.id, t.body, t.created_on, t.author_handle]
  end
  import_timeline_pieces(mapped)
  status 200
end

def import_timeline_pieces(pieces)
  columns = %i[timeline_owner_id tweet_id tweet_body tweet_created_on tweet_author_handle]
  TimelinePiece.import columns, pieces
end
