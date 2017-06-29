require 'csv'
require 'tmpdir'

unless AppConfig.has_key?(:cv_merger)
  AppConfig[:cv_merger] = {
    path: File.join('/tmp', 'aspace', 'merger.csv'),
    retry_if_not_found: true
  }
end

# CSV should have headers: enumeration, old_value, new_value

def self.get_enum_value(enum, value, lowercase = false)
  value = value.downcase if lowercase
  enum_value = enum.enumeration_value.find do |val|
    val[:value] == value
  end
  return enum_value, value
end

def self.retry?(value)
  retry_if_not_found = AppConfig[:cv_merger][:retry_if_not_found]
  retry_if_not_found && value != value.downcase
end

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
              encoding: 'UTF-8',
              converters: ->(f) { f ? f.strip : nil },
              headers: true,
              header_converters: :symbol) do |row|
    rows += 1
    data = row.to_hash
    begin
      enumeration = data[:enumeration]
      old_value   = data[:old_value]
      new_value   = data[:new_value]
      unless enumeration && old_value && new_value
        skipped += 1
        next
      end

      enum = $cv_merger_enums.fetch(enumeration, Enumeration[name: enumeration])
      raise NotFoundException, "Unable to find enumeration '#{enumeration}'" unless enum
      $cv_merger_enums[enumeration] = enum unless $cv_merger_enums.has_key? enumeration
      $cv_merger_nvals[enumeration] = {}   unless $cv_merger_nvals.has_key? enumeration

      # enum.migrate doesn't check for nil old_value so do it here
      old_enum_value, _ = get_enum_value enum, old_value
      if !old_enum_value && retry?(old_value)
        $stdout.puts "Retrying old value '#{old_value}' as '#{old_value.downcase}'"
        old_enum_value, old_value = get_enum_value(enum, old_value, true)
      end

      # cache new values: could be used for merge destination multiple times
      new_enum_value, _ = $cv_merger_nvals[enumeration].fetch(
        new_value, get_enum_value(enum, new_value)
      )

      if !new_enum_value && retry?(new_value)
        $stdout.puts "Retrying new value '#{new_value}' as '#{new_value.downcase}'"
        new_enum_value, new_value = get_enum_value(enum, new_value, true)
      end

      unless $cv_merger_nvals[enumeration].has_key? new_value
        $cv_merger_nvals[enumeration][new_value] = new_enum_value
      end

      unless old_enum_value
        raise NotFoundException, "Unable to find old_value '#{old_value}' in enumeration '#{enumeration}'"
      end

      unless new_enum_value
        raise NotFoundException, "Unable to find new_value '#{new_value}' in enumeration '#{enumeration}'"
      end

      if old_value == new_value
        raise Exception, "Unable to merge '#{old_value}' into itself"
      end

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
