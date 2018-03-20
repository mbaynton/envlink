# Envlink
[![Build Status](https://travis-ci.org/mbaynton/envlink.svg?branch=master)](https://travis-ci.org/mbaynton/envlink)

A little ruby thingamajig intended to execute after
[r10k](https://github.com/puppetlabs/r10k) deploys on your Puppet master.
It ensures symlinks exist inside your Puppet environments according to a
few configurable rules.

The intended use case is to share common hiera data or Puppet modules across
several Puppet environments while allowing changes to those shared resources to
be easily testable in designated test environments, and easy to deploy to
production infrastructure during scheduled maintenance windows.

For example, suppose you have:
  * Four Puppet environments:
      * `servers_production` and `workstations_production`,
        which contain the current state of production servers and workstations,
        respectively;
      * `servers_develop` and `workstations_develop`, which contain the next
        candidate state for servers and workstations, to be rolled out to the
        `_production` environments during an upcoming scheduled maintenance window.
  * a module called `my_base_config` that provides configuration desirable on
    every node in your organization, regardless of Puppet environment.
    
The traditional way to share your code in `my_base_config` around in all four of
your Puppet environments would be to reference a repository
containing various branches of `my_base_config` in the Puppetfiles of all four
environments. That's fine, but what happens when you want to make a change to 
your `my_base_config` module, and test it on a node or two before it lands on
your production systems?  
Without envlink, the change / test workflow would be something like this:
  1. Create a new branch of one of your control repositories and thus a new
     Puppet environment.
  2. Create a new branch of `my_base_config` in which to develop / test your
     change.
  3. Modify the Puppetfile in your new branch of the control repo to reference 
     your new branch of `my_base_config`
  4. Push both new branches to your vcs system / Puppet master
  5. Run your changes on a test node in your new Puppet environment; if outcome
     is not as desired, modify your branch of `my_base_config` and iterate.
  6. When changes are testing out as desired, merge your changes to a branch of
     `my_base_config` that is used in the Puppetfiles of the `servers_develop` and
     `workstations_develop` environments

...and the maintenance day production deployment procedure would be something like
  1. Merge the develop branch of `my_base_config` to the production branch.
  2. If any changes were made to the control repository since the last maintenance 
     window, merge those changes into the `_production` branch too, being careful
     *not* to inadvertently merge the line in the `_develop` branch's Puppetfile
     referencing the develop branch of `my_base_config`, because then your module's
     develop branch would end up being used in production.
     
With envlink, you can write a configuration file, separate from any Puppetfile,
that says
  <font style="color: black !important">
  > "Always associate the `production` branch of `my_base_config` with both of my
    production environments, `servers_production` and `workstations_production`.
    Associate the `develop` branch of `my_base_config` with both of my develop
    environments, `servers_develop` and `workstations_develop` *and* any other
    environments that may get created by people creating new control repo branches,
    *unless* there's a branch of `my_base_config` whose name exactly matches the
    name of the Puppet environment."
  </font>

Now the change / test workflow becomes
  1. Create a new branch of one of your control repositories and thus a new
     Puppet environment.
  2. Create a new branch of `my_base_config`, taking care to name your branch
     to match the name of the Puppet environment you just created.
  3. Push both new branches to your vcs system / Puppet master. Envlink
     figures out what you're trying to do and links the test branch of `my_base_config`
     into the test Puppet environment.
  4. Run your changes on a test node in your test Puppet environment; if outcome
     is not as desired, modify your branch of `my_base_config` and iterate.
  5. When changes are testing out as desired, merge your changes to the `develop`
     branch of `my_base_config.`

..and the maintenance day production deployment procedure becomes
  1. Fast-forward merge of `my_base_config:develop` to `my_base_config:production`
  2. Fast-forward merge of any control repositories' `_develop` branches to
     `_production`. Since the Puppetfile in `_develop` is no different from the
     one in `_production`, there's no manual merges to screw up during the
     maintenance window.
     
## Installation
```bash
$ git clone https://github.com/mbaynton/envlink.git
$ cd envlink
$ # Install dependencies via bundler
$ bundle install
```

## Usage
```bash
$ exe/envlink
```

## Configuration
envlink is configured via a .yaml file. You can specify its location with the `-c`
switch at runtime, or place it at the default location: `/etc/puppetlabs/envlink/envlink.yaml`

The configuration file contains three values at its root level:
  * `r10k_yaml`: Path to r10k's configurtion file. Additional parameters are read from this yaml file.
  * `environment_path`: Path to the directory where r10k places your Puppet environments.
  * `links`: A hash keyed by r10k source names (as listed in your `r10k.yaml`).  
     Each hash contains an array of hashes that describe which symlinks envlink should ensure exist within
     that r10k source, and the rules it should use to determine their targets.
     
### Example configuration files
envlink.yaml:
```yaml
r10k_yaml: /etc/r10k/r10k.yaml
environment_path: /etc/puppetlabs/code/environments

links:
  control_repo_1:
    - link_name: shared_hieradata
      r10k_source: shared_hieradata
      map:
        control_repo_1_production: production
        control_repo_1_test: fred
      fallback_branch: develop
  control_repo_2:
    - link_name: the_shared_hieradata
      r10k_source: shared_hieradata
      map:
        control_repo_2_production: production
      fallback_branch: develop
```

Corresponding r10k.yaml:
```yaml
  sources:
    control_repo_1:
      remote: git@github.com:me/my-things.git
      basedir: '/etc/puppetlabs/code/environments'
      prefix: true

    control_repo_2:
      remote: git@github.com:me/my-other-things.git
      basedir: '/etc/puppetlabs/code/environments'
      prefix: true

    shared_hieradata:
      remote: git@github.com:me/shared_hieradata.git
      basedir: /etc/puppetlabs/code/shared_hieradata
```

These files will result in envlink ensuring the following symbolic links are present:
  - `/etc/puppetlabs/code/environments/control_repo_1_production/shared_hieradata -> /etc/puppetlabs/code/shared_hieradata/production`  
    This link is created because `/etc/puppetlabs/code/environments/control_repo_1_production`
    is a Puppet environment corresponding to the `control_repo_1` r10k source, and `envlink.yaml`
    requests a link inside each environment created by that source called `shared_hieradata`.
    The link target is specified explicitly in the `map` to point to the `production` branch of
    the link's `r10k_source`.
  - `/etc/puppetlabs/code/environments/control_repo_1_test/shared_hieradata -> /etc/puppetlabs/code/shared_hieradata/fred`  
    This link is created according to exactly the same rationale as above.
  - `/etc/puppetlabs/code/environments/control_repo_2_production/the_shared_hieradata -> /etc/puppetlabs/code/shared_hieradata/production`  
    This link is created according to the explicit maps specified for r10k source `control_repo_2`. It
    demonstrates how the `production` branch of the `shared_hieradata` source can be shared by
    `control_repo_1_production` and `control_repo_2_production`.
  - `/etc/puppetlabs/code/environments/control_repo_1_feature/shared_hieradata -> [???]`  
    This link would be created if you were to create a branch of `control_repo_1` called `feature`.
    Since there is not an explicit mapping to a target branch of `shared_hieradata` specified
    for an environment called `control_repo_1_feature`, the target of the link will depend on
    whether or not there is a branch of `shared_hieradata` called (exactly) `control_repo_1_feature`.
    If that branch exists, `envlink` will assume you want to use it in the Puppet environment
    by that name, and will create the symlink to make that happen:
    > `/etc/puppetlabs/code/environments/control_repo_1_feature/shared_hieradata -> /etc/puppetlabs/code/shared_hieradata/control_repo_1_feature`

    Otherwise, it will assume you created the `control_repo_1_feature` environment for purposes other
    than testing changes to `shared_hieradata`, and will use the `fallback_branch`:
    > `/etc/puppetlabs/code/environments/control_repo_1_feature/shared_hieradata -> /etc/puppetlabs/code/shared_hieradata/develop`
    
 ## Tests
 Some simple tests that run `envlink` and verify it creates the expected links have been developed
 under the `test/` directory. To run them, run `test/testme.sh` from the repository root directory.
 
 Several files will be left in `/tmp` for manual examination after the test run completes.
 `.out` files contain anything `envlink` produced on stdout; `.err` files on stderr. `.symlink` files contain
 a listing of the symbolic links that were present after `envlink` ran. 