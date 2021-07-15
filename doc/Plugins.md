# Plugins

<!-- md-toc-begin -->
* [About](#about)
* [Plang](Plugins/Plang.md)
* [Quotegrabs](Plugins/Quotegrabs.md)
<!-- md-toc-end -->

## About
A Plugin is an independent unit of PBot code that can be loaded and unloaded at will.
Plugins have full access to PBot internal APIs and state.

The default plugins loaded by PBot is set by the [`plugin_autoload`](../data/plugin_autoload)
file in your data-directory. To autoload additional plugins, add their name to this file.

The plugins that come with PBot live in [`lib/PBot/Plugin/`](../lib/PBot/Plugin). Additional third-party
plugins may be installed to `~/.pbot/PBot/Plugin/`.

This is the woefully incomplete documentation for the plugins. For more documentation,
browse the headers of the various plugin source files.

## [Plang](Plugins/Plang.md)
Scripting interface to PBot.

## [Quotegrabs](Plugins/Quotegrabs.md)
Grabs and stores user messages for posterity.
