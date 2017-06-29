# cv_merger

Merge controlled values using a CSV file.

## Usage

The CSV requires these headers:

- enumeration (name i.e. `extent_extent_type`)
- old_value (enumeration value to merge away)
- new_value (enumeration value to merge into)

On startup the plugin will process the csv. For each row it will
verify that the enumeration, old and new values exist. If those
preconditions are met then `old_value` will be merged into `new_value`.

This process may delay application startup time so plan accordingly.

## Configuration

By default the CSV is looked for in `/tmp/aspace/merger.csv`.

```ruby
AppConfig[:cv_merger] = {
  path: File.join("/tmp", "aspace", "merger.csv"),
}
```

You may prefer to use something like: `File.join(Dir.tmpdir, "aspace", "merger.csv"),`.

## License

This project is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

---