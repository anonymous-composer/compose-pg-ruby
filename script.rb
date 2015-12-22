#!/usr/bin/env ruby

require 'pg'

unless ENV["COMPOSE_USERNAME"] and ENV["COMPOSE_PASSWORD"]
  puts "Envionment variables COMPOSE_USERNAME and COMPOSE_PASSWORD must exist."
  exit 1
end

#########################################
# Step 1: Connect to a remote database.
#########################################

conn = PG::Connection.new({:user => ENV["COMPOSE_USERNAME"],
                           :password => ENV["COMPOSE_PASSWORD"],
                           :dbname => "compose",
                           :host => "aws-us-east-1-portal.9.dblayer.com",
                           :port => "10366",
                           :sslmode => "require"})


#########################################
# Step 2: Import data into the DB.
#########################################

# Drop any data that already exists.
conn.exec("DROP TABLE IF EXISTS players;")
conn.exec("DROP TABLE IF EXISTS teams;")

# Create a table for storing hockey teams.
conn.exec(%q{
    CREATE TABLE teams (
        id INT PRIMARY KEY,
        name VARCHAR(100),
        division VARCHAR(20),
        founding_year INT
    );
})

# Create a table for storing hockey players.
conn.exec(%q{
    CREATE TABLE players (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100),
        number INT,
        age INT,
        shoots CHAR(1),
        team_id INTEGER REFERENCES teams
    );
})

# Choose the IDs for the teams.
SABRES_ID = 1
LEAFS_ID = 2

# Add a few rows to the teams table.
conn.exec_params(%q{
    INSERT INTO teams (id, name, division, founding_year) VALUES
        ($1, 'Buffalo Sabres', 'Atlantic', 1970),
        ($2, 'Toronto Maple Leafs', 'Atlantic', 1917);
}, [SABRES_ID, LEAFS_ID])

# Add players to our table and assign them to their teams.
conn.exec_params(%q{
    INSERT INTO players (name, number, age, shoots, team_id) VALUES
        ('Jack Eichel',       15, 19, 'R', $1),
        ('Zemgus Girgensons', 28, 21, 'L', $1),
        ('David Legwand',     17, 35, 'L', $1),
        ('Cody McCormick',     8, 32, 'R', $1),
        ('Cal O''Reilly',     19, 29, 'L', $1),
        ('Ryan O''Reilly',    90, 24, 'L', $1),
        ('Sam Reinhart',      23, 20, 'R', $1),
        ('Tyler Bozak',       42, 29, 'R', $2),
        ('Byron Froese',      56, 24, 'R', $2),
        ('Peter Holland',     24, 24, 'L', $2),
        ('Nazem Kadri',       43, 25, 'L', $2),
        ('Leo Komarov',       47, 28, 'L', $2),
        ('Shawn Matthias',    23, 27, 'L', $2),
        ('Nick Spaling',      16, 27, 'L', $2)
}, [SABRES_ID, LEAFS_ID])

#########################################
# Step 3: Query some data out of the DB.
#########################################

# Let's look at all of the teams.
# Use the block syntax.
# Each row is a Ruby Hash with the column names as keys.

conn.exec("SELECT * FROM teams;") do |result|
  puts "The teams:"
  result.each do |row|
    puts " The #{row['name']} were founded in #{row['founding_year']}."
  end
  puts "----"
end

# Let's find the 5 youngest players across both teams.
# Still with block syntax.

conn.exec(%q{
    SELECT p.name AS player, p.age, t.name AS team
    FROM players AS p
    JOIN teams AS t ON t.id = p.team_id
    ORDER BY age ASC
    LIMIT 5;
}) do |result|
  puts "The five youngest players are:"
  result.each do |row|
    puts " #{row['player']} is #{row['age']} and plays for the #{row['team']}."
  end
  puts "----"
end

# Let's find the oldest player on each team.
# Use the Proc syntax for code reuse.

oldest = "SELECT name,age FROM players WHERE team_id=$1 ORDER BY age DESC LIMIT 1;"
get_oldest = Proc.new { |rows| rows.values.flatten }
sabres_oldest = conn.exec_params(oldest, [SABRES_ID], &get_oldest)
leafs_oldest = conn.exec_params(oldest, [LEAFS_ID], &get_oldest)

puts "The oldest center on the Sabres is #{sabres_oldest[0]}. He is #{sabres_oldest[1]}."
puts "The oldest center on the Leafs is #{leafs_oldest[0]}. He is #{leafs_oldest[1]}."
puts "----"

# Let's see which team has the lower average age of their players.

query = "SELECT AVG(age) FROM players WHERE team_id=$1;"
get_avg = Proc.new { |rows| rows.values.flatten.first }
sabres_avg_age = conn.exec_params(query, [SABRES_ID], &get_avg)
leafs_avg_age = conn.exec_params(query, [LEAFS_ID], &get_avg)

if sabres_avg_age > leafs_avg_age
  puts "The Leafs have younger players on average."
else
  puts "The Sabres have younger players on average."
end

conn.close()
