import Config

# The Proxy application should be configured from Umbrella root.
#
# - `:applications` should be a list of application names which will be dynamically
#   included as dependencies.
#
# - `:endpoints` should be a list of {endpoint_module, mount_point}.

config :emporium_proxy, EmporiumProxy,
  applications: [],
  endpoints: []
