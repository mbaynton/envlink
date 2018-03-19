# Envlink

A little ruby thingamajig intended to execute after
[r10k](https://github.com/puppetlabs/r10k) deploys. It ensures symlinks exist
inside your Puppet environments according to a few configurable rules.

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