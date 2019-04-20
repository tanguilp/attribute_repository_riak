# AttributeRepositoryRiak

Riak implementation of `AttributeRepository`

## Installation

```elixir
def deps do
  [
    {:attribute_repository_riak, github: "tanguilp/attribute_repository_riak", tag: "v0.1.0"}
  ]
end
```

## Usage

This modules relies on the `riakc` elixir libray to create and maintain a pool of connections
to a Riak server. Note that this  implementation is not capable of reconnecting.
One shall configure it's server in the relevant configuration files. Example:

```elixir
use Mix.Config

config :pooler, pools: [
  [
    name: :riak,
    group: :riak,
    max_count: 10,
    init_count: 5,
    start_mfa: {Riak.Connection, :start_link, ['127.0.0.1', 8087]}
  ]
]
```

You might want to configure Riak by adding a new bucket type:
```sh
$ sudo riak-admin bucket-type create attr_rep '{"props":{"datatype":"map", "backend":"leveldb_mult"}}'
attr_rep created

$ sudo riak-admin bucket-type activate attr_rep
attr_rep has been activated
```

When calling the `AttributeRepositoryRiak.install/2` function, a new schema is created
(with specific indexing settings for dates) and a search index using this schema is created
at the bucket level. For instance, with `run_opts = [instance: :user, bucket_type: "attr_rep"]`,
the following configuration is set:
- creation of the `attribute_repository_schema` (shared)
- creation of the `attribute_repository_user_index`
- association of that index to the `"user"` bucket in the `"attr_rep"` bucket type
  - The index is *not* associated with the whole bucket type, so as not to mix results between
  different buckets

## Resource id

The resource id of the `AttributeRepositoryRiak` implementation is an arbitrary `String.t()`.

## Run options

The `AttributeRepository.run_opts()` for this module are the following:
- `:instance`: instance name (an `atom()`), **mandatory**
- `:bucket_type`: a `String.t()` for the bucket type that must be created beforehand,
**mandatory**

## Supported behaviours

- [x] `AttributeRepository.Install`
- [x] `AttributeRepository.Read`
- [x] `AttributeRepository.Write`
- [x] `AttributeRepository.Search`

## Supported attribute types

### Data types

- [x] `String.t()`
- [x] `boolean()`
- [ ] `float()`
- [x] `integer()`
- [x] `DateTime.t()`
- [x] `AttributeRepository.binary_data()`
  - Note: fields of this type are not searchable, and are not returned by the search
- [ ] `AttributeRepository.ref()`
- [ ] `nil`
- [ ] `AttributeRepository.object_attribute()` or *complex attribute* (note: this is not
supported by the Riak data model - there are no sets of maps)

### Cardinality

- [x] Singular attributes
- [x] Multi-valued attributes
  - Only for `String.t()` values

## Search support

### Logical operators

- [x] `and`
- [x] `or`
- [x] `not`

### Compare operators

- [x] `eq`
- [x] `ne`
- [x] `gt`
- [x] `ge`
- [x] `lt`
- [x] `le`
- [x] `pr`
- [x] `sw`
- [x] `ew`
- [x] `co`
