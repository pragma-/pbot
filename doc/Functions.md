# Functions

This is a place-holder from the main [README](../README.md#functions) until I have time to flesh this out more.
If you've already read that section, there is nothing new here.

Functions are commands that accept input, manipulate it and then output the result. They are extremely
useful with [piping](../README.md#piping) or [command substituting](../README.md#substitution).

For example, the `uri_escape` function demonstrated in the [Substitutions](../README.md#substitutions) section earlier
makes text safe for use in a URL. We also saw the `sed` and `uc` functions demonstrated in [Piping](../README.md#piping).

    <pragma-> uri_escape thing's & words
       <PBot> thing%27s%20%26%20words

As demonstrated previously, the `sed` function replaces text using a substitution regex. The `uc` function
uppercases the text.

    <pragma-> echo Hello world! | {sed s/world/universe/} | {uc}
       <PBot> HELLO UNIVERSE!

Here's a short list of the Functions that come with PBot.

Name | Description
--- | ---
`uri_escape` | Percent-encodes unsafe URI characters.
`sed` | Performs sed-like regex substitution.
`pluralize` | Intelligently makes a word or phrase plural.
`unquote` | Removes surrounding quotation marks.
`title` | Title-cases text. That is, lowercases the text then uppercases the first letter of each word.
`ucfirst` | Uppercases the first character of the text.
`uc` | Uppercases all characters.
`lc` | Lowercases all characters.
