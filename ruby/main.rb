# Kryptic Ruby package verification: injects secrets from the local daemon and
# reports what landed in ENV.
require "kryptic"

before = ENV.keys

result = Kryptic.inject!

if result.skipped
  puts "SKIPPED (#{result.reason}) - nothing injected."
  puts "If you expected secrets: is the daemon running (`kryptic status`) and are you signed in?"
  exit 1
end

injected = (ENV.keys - before).sort

puts "injected #{result.injected} secret(s):"
injected.each do |key|
  puts "  env     #{key} = #{ENV[key]}"
end

puts "  (the project has no secrets in this environment)" if injected.empty?
