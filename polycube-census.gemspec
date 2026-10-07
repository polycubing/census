# frozen_string_literal: true

require_relative "lib/census/version"

# Never released as a gem. This file exists so the site can point Bundler at
# a checkout (`gem "polycube-census", path: "../census"`) and reuse the
# geometry: Polycube, Rotation, Assembly, JSONDocument, Stages. Those files
# load on their own, so a consumer requires the ones it needs and never pulls
# in the pipeline, the solvers, or the @home layer.
Gem::Specification.new do |spec|
  spec.name = "polycube-census"
  spec.version = Census::VERSION
  spec.authors = ["Shane Becker"]
  spec.summary = "A machine-verified census of which small polycubes tile space"
  spec.homepage = "https://polycubes.org"
  spec.license = "CC0-1.0"
  spec.required_ruby_version = ">= 4.0"
  spec.files = Dir["lib/**/*.rb"]
  spec.metadata["rubygems_mfa_required"] = "true"
end
