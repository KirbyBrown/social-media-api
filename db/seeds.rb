# frozen_string_literal: true

password = "password123"

# Inline adapter so seeding does not require Redis. Rating upserts enqueue
# NotifyJob and WarmJob; inline runs them synchronously instead of failing
# when Sidekiq cannot connect.
previous_adapter = ActiveJob::Base.queue_adapter
ActiveJob::Base.queue_adapter = :inline

begin
  if Rails.env.development?
    Rating.delete_all
    Post.delete_all
    User.delete_all
  end
  kirby = User.find_or_create_by!(username: "kirby") do |user|
    user.email = "kirby@example.com"
    user.password = password
  end
  jack = User.find_or_create_by!(username: "jack") do |user|
    user.email = "jack@example.com"
    user.password = password
  end
  eric = User.find_or_create_by!(username: "eric") do |user|
    user.email = "eric@example.com"
    user.password = password
  end

  scan = kirby.posts.find_or_create_by!(title: "First OBD scan") do |post|
    post.body = "Codes from the morning lot walk."
    post.metadata = { "source" => "obd", "vin" => "1HGCM82633A004352" }
  end
  notes = jack.posts.find_or_create_by!(title: "Shop notes") do |post|
    post.body = "Unrated writeup. Should still show on the unfiltered timeline."
    post.metadata = { "source" => "manual" }
  end
  favorite = eric.posts.find_or_create_by!(title: "Clean title, clean scan") do |post|
    post.body = "This one should sit near the top of a min_rating=4 feed."
    post.metadata = { "source" => "obd" }
  end
  gone = kirby.posts.find_or_create_by!(title: "Deleted draft") do |post|
    post.body = "Soft-deleted. List and timeline should omit it."
  end
  gone.soft_delete if gone.kept?

  Ratings::Upsert.new(user: jack, post: scan, value: 4).call
  Ratings::Upsert.new(user: eric, post: scan, value: 5).call
  Ratings::Upsert.new(user: kirby, post: favorite, value: 5).call
  Ratings::Upsert.new(user: jack, post: favorite, value: 5).call

  puts "Seeded #{User.count} users, #{Post.kept.count} kept posts, #{Post.where.not(deleted_at: nil).count} deleted, #{Rating.count} ratings."
  puts "Log in as kirby@example.com / #{password}. Titles: #{scan.title}, #{notes.title}, #{favorite.title}."
ensure
  ActiveJob::Base.queue_adapter = previous_adapter
end
