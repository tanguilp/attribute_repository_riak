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

Do not use the `"_integer"`, `"_date"` or `"_binarydata"` suffixes as it is used internally
(except if you use it with the same data type as the prefix).

## Example

```elixir
iex> run_opts = [instance: :users, bucket_type: "attr_rep"]
[instance: :users, bucket_type: "attr_rep"]
iex> AttributeRepositoryRiak.install(run_opts, [])
:ok
iex> AttributeRepositoryRiak.put("DKO77TT652NZHXX3WM3ZJBFIC4", %{"first_name" => "Claude", "last_name" => "Leblanc", "shoe_size" => 43, "subscription_date" => DateTime.from_iso8601("2014-06-13T04:42:34Z") |> elem(1)}, run_opts)
{:ok,
 %{
   "first_name" => "Claude",
   "last_name" => "Leblanc",
   "shoe_size" => 43,
   "subscription_date" => #DateTime<2014-06-13 04:42:34Z>
 }}
iex> AttributeRepositoryRiak.put("SGKNRFHMBSKGRVCW4SIJAZMYLE", %{"first_name" => "Xiao", "last_name" => "Ming", "shoe_size" => 36, "subscription_date" => DateTime.from_iso8601("2015-01-29T10:49:58Z") |> elem(1)}, run_opts)
{:ok,
 %{
   "first_name" => "Xiao",
   "last_name" => "Ming",
   "shoe_size" => 36,
   "subscription_date" => #DateTime<2015-01-29 10:49:58Z>
 }}
iex> AttributeRepositoryRiak.put("7WRQL4EAKW27C5BEFF3JDGXBTA", %{"first_name" => "Tomoaki", "last_name" => "Takapamate", "shoe_size" => 34, "subscription_date" => DateTime.from_iso8601("2019-10-13T23:22:51Z") |> elem(1)}, run_opts)
{:ok,
 %{
   "first_name" => "Tomoaki",
   "last_name" => "Takapamate",
   "shoe_size" => 34,
   "subscription_date" => #DateTime<2019-10-13 23:22:51Z>
 }}
iex> AttributeRepositoryRiak.put("WCJBCL7SC2THS7TSRXB2KZH7OQ", %{"first_name" => "Narivelo", "last_name" => "Rajaonarimanana", "shoe_size" => 41, "subscription_date" => DateTime.from_iso8601("2017-06-06T21:01:43Z") |> elem(1), "newsletter_subscribed" => false}, run_opts)
{:ok,
 %{
   "first_name" => "Narivelo",
   "last_name" => "Rajaonarimanana",
   "newsletter_subscribed" => false,
   "shoe_size" => 41,
   "subscription_date" => #DateTime<2017-06-06 21:01:43Z>
 }}
iex> AttributeRepositoryRiak.put("MQNL5ASVNLWZTLJA4MDGHKEXOQ", %{"first_name" => "Hervé", "last_name" => "Le Troadec", "shoe_size" => 48, "subscription_date" => DateTime.from_iso8601("2017-10-19T12:07:03Z") |> elem(1)}, run_opts)
{:ok,
 %{
   "first_name" => "Hervé",
   "last_name" => "Le Troadec",
   "shoe_size" => 48,
   "subscription_date" => #DateTime<2017-10-19 12:07:03Z>
 }}
iex> AttributeRepositoryRiak.put("Y4HKZMJ3K5A7IMZFZ5O3O56VC4", %{"first_name" => "Lisa", "last_name" => "Santana", "shoe_size" => 33, "subscription_date" => DateTime.from_iso8601("2014-08-30T13:45:45Z") |> elem(1), "newsletter_subscribed" => true}, run_opts)
{:ok,
 %{
   "first_name" => "Lisa",
   "last_name" => "Santana",
   "newsletter_subscribed" => true,
   "shoe_size" => 33,
   "subscription_date" => #DateTime<2014-08-30 13:45:45Z>
 }}
iex> AttributeRepositoryRiak.put("4D3FB7C89DC04C808CC756151C", %{"first_name" => "Bigfoot", "shoe_size" => 104, "subscription_date" => DateTime.from_iso8601("1914-10-10T03:42:01Z") |> elem(1)}, run_opts)
{:ok,
 %{
   "first_name" => "Bigfoot",
   "shoe_size" => 104,
   "subscription_date" => #DateTime<1914-10-10 03:42:01Z>
 }}
iex> AttributeRepositoryRiak.get("Y4HKZMJ3K5A7IMZFZ5O3O56VC4", :all, run_opts)
{:ok,
 %{
   "first_name" => "Lisa",
   "last_name" => "Santana",
   "newsletter_subscribed" => true,
   "shoe_size" => 33,
   "subscription_date" => #DateTime<2014-08-30 13:45:45Z>
 }}
iex> AttributeRepositoryRiak.get("Y4HKZMJ3K5A7IMZFZ5O3O56VC4", ["shoe_size"], run_opts)
{:ok, %{"shoe_size" => 33}}
iex> AttributeRepositoryRiak.get!("Y4HKZMJ3K5A7IMZFZ5O3O56VC4", ["shoe_size"], run_opts)
%{"shoe_size" => 33}
iex> AttributeRepositoryRiak.modify("Y4HKZMJ3K5A7IMZFZ5O3O56VC4", [{:replace, "shoe_size", 34}, {:add, "interests", ["rock climbing", "tango", "linguistics"]}], run_opts)
:ok
iex> AttributeRepositoryRiak.get!("Y4HKZMJ3K5A7IMZFZ5O3O56VC4", :all, run_opts)
%{
  "first_name" => "Lisa",
  "interests" => ["linguistics", "rock climbing", "tango"],
  "last_name" => "Santana",
  "newsletter_subscribed" => true,
  "shoe_size" => 34,
  "subscription_date" => #DateTime<2014-08-30 13:45:45Z>
}
iex> AttributeRepositoryRiak.search(~s(last_name eq "Ming"), :all, run_opts)
[
  {"SGKNRFHMBSKGRVCW4SIJAZMYLE",
   %{
     "first_name" => "Xiao",
     "last_name" => "Ming",
     "shoe_size" => 36,
     "subscription_date" => #DateTime<2015-01-29 10:49:58Z>
   }}
]
iex> AttributeRepositoryRiak.search(~s(last_name eq "Ming"), ["shoe_size", "subscription_date"], run_opts)
[
  {"SGKNRFHMBSKGRVCW4SIJAZMYLE",
   %{"shoe_size" => 36, "subscription_date" => #DateTime<2015-01-29 10:49:58Z>}}
]
iex> AttributeRepositoryRiak.search(~s(last_name ew "ana"), :all, run_opts)
[
  {"WCJBCL7SC2THS7TSRXB2KZH7OQ",
   %{
     "first_name" => "Narivelo",
     "last_name" => "Rajaonarimanana",
     "newsletter_subscribed" => false,
     "shoe_size" => 41,
     "subscription_date" => #DateTime<2017-06-06 21:01:43Z>
   }},
  {"Y4HKZMJ3K5A7IMZFZ5O3O56VC4",
   %{
     "first_name" => "Lisa",
     "interests" => ["linguistics", "rock climbing", "tango"],
     "last_name" => "Santana",
     "newsletter_subscribed" => true,
     "shoe_size" => 34,
     "subscription_date" => #DateTime<2014-08-30 13:45:45Z>
   }}
]
iex> AttributeRepositoryRiak.search(~s(last_name co "Le"), :all, run_opts)
[
  {"DKO77TT652NZHXX3WM3ZJBFIC4",
   %{
     "first_name" => "Claude",
     "last_name" => "Leblanc",
     "shoe_size" => 43,
     "subscription_date" => #DateTime<2014-06-13 04:42:34Z>
   }},
  {"MQNL5ASVNLWZTLJA4MDGHKEXOQ",
   %{
     "first_name" => "Hervé",
     "last_name" => "Le Troadec",
     "shoe_size" => 48,
     "subscription_date" => #DateTime<2017-10-19 12:07:03Z>
   }}
]
iex> AttributeRepositoryRiak.search(~s(first_name co "v" or last_name sw "Le"), :all, run_opts)
[
  {"MQNL5ASVNLWZTLJA4MDGHKEXOQ",
   %{
     "first_name" => "Hervé",
     "last_name" => "Le Troadec",
     "shoe_size" => 48,
     "subscription_date" => #DateTime<2017-10-19 12:07:03Z>
   }},
  {"DKO77TT652NZHXX3WM3ZJBFIC4",
   %{
     "first_name" => "Claude",
     "last_name" => "Leblanc",
     "shoe_size" => 43,
     "subscription_date" => #DateTime<2014-06-13 04:42:34Z>
   }},
  {"WCJBCL7SC2THS7TSRXB2KZH7OQ",
   %{
     "first_name" => "Narivelo",
     "last_name" => "Rajaonarimanana",
     "newsletter_subscribed" => false,
     "shoe_size" => 41,
     "subscription_date" => #DateTime<2017-06-06 21:01:43Z>
   }}
]
iex> AttributeRepositoryRiak.search(~s(shoe_size le 40), :all, run_opts)
[
  {"SGKNRFHMBSKGRVCW4SIJAZMYLE",
   %{
     "first_name" => "Xiao",
     "last_name" => "Ming",
     "shoe_size" => 36,
     "subscription_date" => #DateTime<2015-01-29 10:49:58Z>
   }},
  {"7WRQL4EAKW27C5BEFF3JDGXBTA",
   %{
     "first_name" => "Tomoaki",
     "last_name" => "Takapamate",
     "shoe_size" => 34,
     "subscription_date" => #DateTime<2019-10-13 23:22:51Z>
   }},
  {"Y4HKZMJ3K5A7IMZFZ5O3O56VC4",
   %{
     "first_name" => "Lisa",
     "interests" => ["linguistics", "rock climbing", "tango"],
     "last_name" => "Santana",
     "newsletter_subscribed" => true,
     "shoe_size" => 34,
     "subscription_date" => #DateTime<2014-08-30 13:45:45Z>
   }}
]
iex> AttributeRepositoryRiak.search(~s(shoe_size le 40 and newsletter_subscribed eq true), :all, run_opts)
[
  {"Y4HKZMJ3K5A7IMZFZ5O3O56VC4",
   %{
     "first_name" => "Lisa",
     "interests" => ["linguistics", "rock climbing", "tango"],
     "last_name" => "Santana",
     "newsletter_subscribed" => true,
     "shoe_size" => 34,
     "subscription_date" => #DateTime<2014-08-30 13:45:45Z>
   }}
]
iex> AttributeRepositoryRiak.search(~s(subscription_date gt "2015-06-01T00:00:00Z"), :all, run_opts)
[
  {"7WRQL4EAKW27C5BEFF3JDGXBTA",
   %{
     "first_name" => "Tomoaki",
     "last_name" => "Takapamate",
     "shoe_size" => 34,
     "subscription_date" => #DateTime<2019-10-13 23:22:51Z>
   }},
  {"MQNL5ASVNLWZTLJA4MDGHKEXOQ",
   %{
     "first_name" => "Hervé",
     "last_name" => "Le Troadec",
     "shoe_size" => 48,
     "subscription_date" => #DateTime<2017-10-19 12:07:03Z>
   }},
  {"WCJBCL7SC2THS7TSRXB2KZH7OQ",
   %{
     "first_name" => "Narivelo",
     "last_name" => "Rajaonarimanana",
     "newsletter_subscribed" => false,
     "shoe_size" => 41,
     "subscription_date" => #DateTime<2017-06-06 21:01:43Z>
   }}
]
iex> AttributeRepositoryRiak.search(~s(interests eq "rock climbing"), :all, run_opts)
[
  {"Y4HKZMJ3K5A7IMZFZ5O3O56VC4",
   %{
     "first_name" => "Lisa",
     "interests" => ["linguistics", "rock climbing", "tango"],
     "last_name" => "Santana",
     "newsletter_subscribed" => true,
     "shoe_size" => 34,
     "subscription_date" => #DateTime<2014-08-30 13:45:45Z>
   }}
]
iex> AttributeRepositoryRiak.search("not (shoe_size lt 100)", :all, run_opts)
[
  {"4D3FB7C89DC04C808CC756151C",
   %{
     "first_name" => "Bigfoot",
     "shoe_size" => 104,
     "subscription_date" => #DateTime<1914-10-10 03:42:01Z>
   }}
]
```

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
- [ ] `AttributeRepository.SupervisedStart`
- [ ] `AttributeRepository.Start`

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

## TODO

- [ ] Test suite

- [ ] `float()` data type (through SOLR index)
