class Query

  attr_accessor :database

  attr_accessor :name
  attr_accessor :sql

  attr_accessor :start_at, :end_at

  def initialize(database, opts = {})
    self.database = database
    
    self.name = opts[:name].to_sym || :general
    self.start_at = Time.parse(opts[:start_at]) if opts[:start_at].present?
    self.end_at   = Time.parse(opts[:end_at])   if opts[:end_at].present?
  end

  def fetch
    database.fetch(query, start_at, end_at)
  end

  def fetch_all_as_json
    {
      'name' =>     name,
      'start_at' => start_at,
      'end_at' =>   end_at,
      'data' =>     fetch.all
    }
  end

  def start_at
    (@start_at || (Time.now - 1.month).beginning_of_month).beginning_of_day
  end

  def end_at
    (@end_at || start_at.end_of_month).end_of_day
  end

  def query
    case name.to_sym
    when :general
      general_analysis_query
    when :users_evolution
      users_evolution_query
    when :users_rides
      user_rides_query
    end
  end

  protected

  def general_analysis_query
    <<-EOF
SELECT date_part('year', journeys.start_at) as yr, date_part('month', journeys.start_at) as mth, date_part('day', journeys.start_at) as day, to_char(journeys.start_at,'day') as wkday , journeys.region_id, journeys.start_type, journeys.end_state, journeys.currency , case when journeys.currency = 'MXN' then (journeys.price * 0.0008) when journeys.currency = 'CLP' then (journeys.price * 0.002) when journeys.currency = 'PEN' then (journeys.price * 0.0036) when journeys.currency = 'EUR' then (journeys.price * 0.0132) end as usd, journeys.distance, journeys.duration / 60 as dur_min, journeys.rider_waiting_time / 60 as rider_wait
FROM users INNER JOIN journeys ON (users.user_id = journeys.user_id) WHERE journeys.start_at >= ? AND journeys.start_at <= ? AND users.role = 'user' ORDER BY journeys.region_id, journeys.end_state, yr, mth desc;
    EOF
  end

  def users_evolution_query
    <<-EOF
SELECT    journeys.region_id,    users.source,    cast(extract(year from date_trunc('month', users.created_at)) as text) ||'_'|| to_char(extract(month from date_trunc('month', users.created_at)),'FM00') as cohort,    to_char(EXTRACT(year FROM age(date_trunc('month', journeys.start_at),date_trunc('month', users.created_at)))*12 + EXTRACT(month FROM age(date_trunc('month',    journeys.start_at),date_trunc('month', users.created_at))),'FM00') as acct_age,    count(*) as nbr_rides,    count(distinct journeys.user_id) as nbr_users,    round(sum(case when currency = 'MXN' then (price * 0.0008) when currency = 'CLP' then (price * 0.002) when currency = 'PEN' then (price * 0.0036)    when currency = 'EUR' then (price * 0.0132) end),2) as USD FROM users inner join journeys on (users.user_id = journeys.user_id)
WHERE    users.role = 'user' and    journeys.end_state = 'drop off'
AND users.created_at >= ?
AND users.created_at <= ?
GROUP BY    journeys.region_id,    users.source,    date_trunc('month', users.created_at),    date_trunc('month', journeys.start_at) ORDER BY    region_id, cohort, acct_age    ;
    EOF
  end

  def user_rides_query
    <<-EOF
WITH set1 as(
SELECT count(*) as tot_rides_per_user,
  (EXTRACT(year FROM age(date_trunc('month', current_date),date_trunc('month', users.created_at)))*12 + EXTRACT(month FROM age(date_trunc('month', current_date),date_trunc('month', users.created_at))) + 1) as mob,
  round(cast(count(*)/(EXTRACT(year FROM age(date_trunc('month', current_date),date_trunc('month', users.created_at)))*12 + EXTRACT(month FROM age(date_trunc('month', current_date),date_trunc('month', users.created_at))) + 1) as numeric),1) as avg_rides_per_user_per_mth,
  journeys.region_id,
  users.source,
  cast(extract(year from date_trunc('month', users.created_at)) as text) ||'_'|| to_char(extract(month from date_trunc('month', users.created_at)),'FM00') as cohort
FROM public.users inner join public.journeys on (users.user_id = journeys.user_id)  
WHERE    users.role = 'user' and    journeys.end_state = 'drop off' 
AND users.created_at >= ?
AND users.created_at <= ?
GROUP BY    journeys.region_id, journeys.user_id, users.source, date_trunc('month', users.created_at)
)
SELECT
  region_id,
  cohort,
  source,
  CASE  WHEN ( 0 <  avg_rides_per_user_per_mth AND avg_rides_per_user_per_mth <=  1) THEN '1. ]0,1]'
    WHEN ( 1 <= avg_rides_per_user_per_mth AND avg_rides_per_user_per_mth <=  2) THEN '2. ]1,2]'
    WHEN ( 2 <= avg_rides_per_user_per_mth AND avg_rides_per_user_per_mth <=  3) THEN '3. ]2,3]'
    WHEN ( 3 <= avg_rides_per_user_per_mth AND avg_rides_per_user_per_mth <=  5) THEN '4. ]3,5]'
    WHEN ( 5 <= avg_rides_per_user_per_mth AND avg_rides_per_user_per_mth <= 10) THEN '5. ]5,10]'
    WHEN (10 <= avg_rides_per_user_per_mth AND avg_rides_per_user_per_mth <= 30) THEN '6. ]10,30]'
    WHEN (30 <= avg_rides_per_user_per_mth) THEN '7. ]30,+]'
  END as bin,
  count(*) as users_in_bin
FROM  set1
GROUP BY region_id, cohort, source, bin
    EOF
  end


  class << self

    def options
      [:general]
    end

  end

end
