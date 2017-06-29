require 'csv'
require 'tmpdir'

unless AppConfig.has_key?(:cv_merger)
  AppConfig[:cv_merger] = {
    path: File.join("/tmp", "aspace", "merger.csv"),
  }
end

# CSV should have headers: enumeration, old_value, new_value

$cv_merger_path  = AppConfig[:cv_merger][:path]
$cv_merger_enums = {}
$cv_merger_nvals = {}

$stdout.puts "\n\n\ncv_merger active for #{$cv_merger_path}\n\n\n"

if File.file?($cv_merger_path)
  # counts
  rows    = 0
  skipped = 0
  merged  = 0
  errors  = 0

  CSV.foreach($cv_merger_path,
    {
      encoding: "UTF-8",
      headers: true,
      header_converters: :symbol,
    }) do |row|
    rows += 1
    data = row.to_hash
    begin
      enumeration = data[:enumeration]
      old_value   = data[:old_value]
      new_value   = data[:new_value]
      unless enumeration and old_value and new_value
        skipped += 1
        next
      end

      enum = $cv_merger_enums.fetch(enumeration, Enumeration[name: enumeration])
      raise NotFoundException.new("Unable to find enumeration '#{enumeration}'") unless enum
      $cv_merger_enums[enumeration] = enum unless $cv_merger_enums.has_key? enumeration
      $cv_merger_nvals[enumeration] = {}   unless $cv_merger_nvals.has_key? enumeration

      # enum.migrate doesn't check for nil old_value so lets head it off
      old_enum_value = enum.enumeration_value.find { |val| val[:value] == old_value }
      
      # cache new values as they could be used for merge destination multiple times
      new_enum_value = $cv_merger_nvals[enumeration].fetch(new_value, enum.enumeration_value.find {
        |val| val[:value] == new_value
      })
      $cv_merger_nvals[enumeration][new_value] = new_enum_value unless $cv_merger_nvals[enumeration].has_key? new_value
      
      raise NotFoundException.new(
        "Unable to find old_value '#{old_value}' in enumeration '#{enumeration}'"
      ) unless old_enum_value
      
      raise NotFoundException.new(
        "Unable to find new_value '#{new_value}' in enumeration '#{enumeration}'"
      ) unless new_enum_value

      $stdout.puts "Merging '#{old_value}' into '#{new_value}' for '#{enumeration}'"
      RequestContext.open(
        current_username: 'admin',
        repo_id: Repository.global_repo_id
      ) do
        enum.migrate old_value, new_value
        merged += 1
      end
    rescue Exception => ex
      $stderr.puts ex.message
      errors += 1
    end
  end
  $stdout.puts "Processed #{rows} rows, skipped #{skipped} and merged #{merged} values with #{errors} errors."
end

$cv_merger_enums = nil
$cv_merger_nvals = nil