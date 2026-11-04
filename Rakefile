# frozen_string_literal: true

require 'rake/testtask'
require 'rubocop/rake_task'

Rake::TestTask.new(:test) do |task|
  task.libs << 'test'
  task.libs << 'lib'
  task.pattern = 'test/**/*_test.rb'
  task.warning = false
end

RuboCop::RakeTask.new(:rubocop)

task default: %i[rubocop test]
