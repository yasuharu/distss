require "rubygems"
require 'rake/testtask'
require 'ci/reporter/rake/test_unit'

# task :test do
# 	ruby "test/network_test.rb"
# end

Rake::TestTask.new do |t|
	t.libs << "test"
	t.test_files = FileList['test/*.rb']
	t.warning = true
	t.verbose = true
end

