require 'sinatra'
require 'haml'
require 'data_mapper'
require './grid'

class Score
  include DataMapper::Resource
  
  property :id,         Serial    # An auto-increment integer key
  property :name,       String
  property :normalized_name, String
  property :time,       String
  property :moves,      Integer
  property :difficulty, String
  property :points,     Float
  property :is_best_score, Boolean, default: false
  property :created_at, DateTime

  CHART_SIZE = 10
  
  def update_best_score
    # find best score
    best = nil
    #scores_same_name = Score.all(name: name, difficulty: difficulty);
    scores_same_name = Score.all(normalized_name: normalized_name)
    #puts normalized_name
    #puts ':::'
    #puts scores_same_name
    #puts '-------------------'
    scores_same_name.each do |s|
      if best == nil || s.points > best.points
        best = s
      end
    end
    scores_same_name.each do |s|
      s.is_best_score = (s == best)
      s.save
      #s.destroy if !s.is_best_score
    end
  end
  
  def self.rename_difficulties
    all().each do |s|
      s.difficulty = case s.difficulty
      when 'easy' then 'easiest'
      when 'medium' then 'easy'
      when 'hard' then 'medium'
      when 'hardest' then 'hard'
      else nil
      end
      s.save
    end
  end
  
  def self.chart(opts={})
    days = opts[:days] || nil
    limit = opts[:limit] || CHART_SIZE
    
    
    options = {order: [:points.desc]}
    if opts[:single_entries]
      options[:is_best_score] = true
    end
    
    if days
      time = Time.now - 60*60*24*days
      options[:created_at.gt] = time
    end
    
    all(options)[0...limit]
  end
  
  def self.recent_chart(opts={})
    num_of_plays = limit = CHART_SIZE
    time = all(order: [:created_at.desc])[num_of_plays].created_at
    all(:created_at.gt => time, order:[:points.desc])[0...limit]
  end
  
  def self.recent_games
    scores = []
    names = {}
    names.default = 0
    all(order: [:created_at.desc]).each do |s|
      name = s.normalized_name
      names[name] += 1
      if names[name] <= 2
        scores << s
        break if scores.size == CHART_SIZE
      end
    end
    scores.sort_by{|x|-x.points}
  end
  
  def self.recent_players
    limit = CHART_SIZE
    res = {} # name to highest score
    all(order: [:created_at.desc]).each do |s|
      # end after 10th name
      # but first check for other games by same authors
      name = s.normalized_name
      isnewname = !res.has_key?(name)
      break if res.size == limit && isnewname
      
      if isnewname or s.points > res[name].points
        res[name] = s
      end
    end
    res.values.sort_by{|x|-x.points}
  end
  
  def update_score
    mins, secs = time.split(':')
    mins = mins.to_f + secs.to_f / 60.0
    time_score = 1.0/mins**0.5
    
    n_cells = {'easiest'=>5*5, 'easy'=>7*7, 'medium'=>9*9, 'hard'=>9*9}
    difficulty_score = n_cells[difficulty]**2
    
    move_score = 0.5**(moves**0.6)
    
    mult_factor = 0.5
    self.points = (mult_factor * difficulty_score * time_score * move_score)**0.5
    save
  end
  
  def self.update_scores
    all().each {|s| s.update_score}
  end

  def self.update_best_scores
    all().each {|s| s.update_best_score}
  end
  def self.strip_names
    all().each {|s|s.name = s.name.strip; s.normalized_name = s.name.downcase; s.save}
  end
  def self.remove_blacklisted
    blacklist = [/a fela/, /fuck/]
    all().each do |s|
      blacklist.each do |m|
        if s.name =~ m
          s.destroy
          break
        end
      end
    end
  end
end

class Item
  include DataMapper::Resource
 
  property :text, String,:key => true
end



 
configure do
  DataMapper.setup(:default, ENV['DATABASE_URL'] || 'postgres://fela:@localhost/net-connect')
  DataMapper.finalize
  #Score.strip_names
  #DataMapper.auto_upgrade!
  #Score.update_best_scores
  #DataMapper.auto_migrate!
  #Score.remove_blacklisted
  DataMapper::Model.raise_on_save_failure = true
  
  #Score.update_scores
  #Score.rename_difficulties
  enable :sessions
end

helpers do  
  include Rack::Utils  
  alias_method :h, :escape_html
  
  def show_hiscores
    @overAllChart = Score.chart(single_entries: true)
    @recentChart = Score.recent_chart
    @recentPeopleChart = Score.recent_players
    haml :hiscores
  end
  
  def partial( page, variables={} )
    haml page.to_sym, {layout:false}, variables
  end
  
  def moves_quality(num)
    case num
    when 0 then 'good'
    when 1..3 then 'average'
    else 'bad'
    end
  end
end  




get '/' do
  @game = Grid.new(wrapping: true)
  haml :index
end

get '/rules' do
  haml :rules
end

get '/privatechart/:order' do
  @chart = Score.all(order: [params[:order].to_sym.desc])
  haml :privatechart
end

post '/gamewon' do
  # params should contain: difficulty, time, moves and the score
  @params = params
  @name = session[:name]
  @chart = Score.recent_players
  haml :submitscore
end

def get_or_post(path, opts={}, &block)
  get(path, opts, &block)
  post(path, opts, &block)
end

post '/submitscore' do
  name = h params[:name][0...14].strip
  if (name.size < 1)
    show_hiscores
    return
  end
  
  time = h params[:time]
  moves = (h params[:moves]).to_i
  difficulty = h params[:difficulty]
  points = params[:points]
  
  session[:name] = name
  
  @newScore = Score.create(name: name, normalized_name: name.downcase, time: time, moves: moves, difficulty: difficulty, points: points, created_at: Time.now)
  @newScore.save
  @newScore.update_best_score
  
  
  show_hiscores
end

get '/hiscores' do
  show_hiscores
end


