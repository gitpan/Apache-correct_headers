package Apache::correct_headers;

$VERSION = sprintf "%d.%02d", q$Revision: 1.16 $ =~ /(\d+).(\d+)/;

__END__

=head1 NAME

correct_headers - A quick guide for mod_perl users

=head1 SYNOPSIS

As there is always more than one way to do it, I'm tempted to
believe one must be the best. Hardly ever am I right.

=head1 DESCRIPTION

=head1 1) Why headers

Dynamic Content is dynamic, after all, so why would anybody care
about HTTP headers? Header composition is an often neglected
task in the CGI world. Because pages are generated dynamically,
you might believe that pages without a Last-Modified header are
fine, and that an If-Modified-Since header in the browser's
request can go by unnoticed. This laissez-faire principle gets
in the way when you try to establish a server that is entirely
driven by dynamic components and the number of hits is
significant.

If the number of hits is not significant, don't bother to read
this document.

If the number of hits is significant, you might want to consider
what cache-friendliness means (you may also want to read [4])
and how you can cooperate with caches to increase the performace
of your site. Especially if you use a squid in accelerator mode
(helpful hints for squid, see [1]), you will have a strong
motivation to cooperate with it. This document may help you to
do it correctly.

=head1 2) Which Headers

The HTTP standard (v 1.1 is specified in [3], v 1.0 in [2])
describes lots of headers. In this document, we only discuss
those headers which are most relevant to caching.

I have grouped the headers in three groups: date headers,
content headers, and the special Vary header.

=head2 2.1) Date related headers

=head2 2.1.1) Date

Section 14.18 of the HTTP standard deals with the circumstances,
under which you must or must not send a Date header. For almost
everything a normal mod_perl user is doing, a Date header needs
to be generated. But the mod_perl programmer doesn't have to
care for this header, the apache server guarantees that this
header is being sent.

In http_protocol.c the Date header is set according to
r->request_time. A modperl script can read, but not change,
r->request_time.

=head2 2.1.2) Last-Modified

Section 14.29 of the HTTP standard deals with this. The
Last-Modified header is mostly used as a so-called weak
validator. I'm citing two sentences from the HTTP specs:

  A validator that does not always change when the resource
  changes is a "weak validator."

  One can think of a strong validator as one that changes
  whenever the bits of an entity changes, while a weak value
  changes whenever the meaning of an entity changes.

This tells us that we should consider the semantics of the page
we are generating and not the date when we are running. The
question is, when did the B<meaning> of this page change last
time? Let's imagine, the document in question is a text-to-gif
renderer that takes as input a font to use, background and
foreground color, and a string to render. Although the actual
image is created on-the-fly, the semantics of the page are
determined when the script has changed the last time, right?

Actually, there are a few more things relevant: the semantics
also change a little when you update one of the fonts that may
be used or when you update your ImageMagick or whatever program.
It's something you should consider, if you want to get it right.

If you have several components that compose a page, you should
ask the question for all components, when they changed their
semantic behaviour last time. And then pick the maximum of those
times.

mod_perl offers you two convenient methods to deal with this
header: update_mtime and set_last_modified. Both these two and
several more methods are not available in the normal mod_perl
environment but get added silently when you require
Apache::File. As of this writing, Apache::File comes without a
manpage, so you have to read about it in Chapter 9 of [5].

update_mtime() takes a UNIX time as argument and sets apache's
request structure finfo.st_mtime to this value. It does so only
when the argument is greater than an already stored
finfo.st_mtime.

set_last_modified() sets the outgoing header C<Last-Modified> to
the string that corresponds to the stored finfo.st_mtime. By
passing a UNIX time to set_last_modified(), mod_perl calls
update_mtime() with this argument first.

  use Apache::File;
  use Date::Parse;
  # Date::Parse parses RCS format, Apache::Util::parsedate doesn't
  $Mtime ||=
    Date::Parse::str2time(substr q$Date: 1999/08/14 06:21:32 $, 6);
  $r->set_last_modified($Mtime);

=head2 2.1.3) Expires and Cache-Control

Section 14.21 of the HTTP standard deals with the Expires
header. The meaning of the Expires header is to determine a
point in time after which this document should be considered out
of date (stale). Don't confuse this with the very different
meaning of the Last-Modified. The Expires header is useful to
avoid unnecessary validation from now on until the document
expires and it helps the recipient to clean up his stored
documents. A sentence from the HTTP standard:

  The presence of an Expires field does not imply that the
  original resource will change or cease to exist at, before, or
  after that time.

So think before you set up a time when you believe, a resource
should be regarded as stale. Most of the time I can determine an
expected lifetime from "now", that is the time of the request. I
would not recommend to hardcode the date of Expiry, because when
you forget that you did that, and the date arrives, you will
serve "already expired" documents that cannot be cached at all
by anybody. If you believe, a resource will never expire, read
this quote from the HTTP specs:

  To mark a response as "never expires," an origin server sends an
  Expires date approximately one year from the time the response is
  sent. HTTP/1.1 servers SHOULD NOT send Expires dates more than one
  year in the future.

Now the code for the mod_perl programmer that wants to expire a
document half a year from now:

  $r->header_out('Expires',
                 HTTP::Date::time2str(time + 180*24*60*60));

A very handy alternative to this computation is available in
HTTP 1.1, the cache control mechanism. Instead of setting the
Expires header you can specify a delta value in a Cache-Control
header. You can do that by running just

  $r->header_out('Cache-Control', "max-age=" . 180*24*60*60);

which is, of course much cheaper than the above because perl
computes the value only once at compile time and optimizes it
away as a constant.

As this alternative is only available in HTTP 1.1 and old cache
servers may not understand this header, it is advisable to send
both headers. In this case the Cache-Control header takes
precedence, so that the Expires header is ignored on HTTP 1.1
complient servers. Or you could go with an if/else clause:

  if ($r->protocol =~ /(\d\.\d)/ && $1 >= 1.1){
    $r->header_out('Cache-Control', "max-age=" . 180*24*60*60);
  } else {
    $r->header_out('Expires',
                   HTTP::Date::time2str(time + 180*24*60*60));
  }

If you restart your apache regularly, I'd save the Expires
header in a global variable. Oh, well, this is probably
over-engineered now.

If people are determined that their document shouldn't be
cached, here is the easy way to set a suitable Expires header...

The call $r->no_cache(1) will cause apache to generate an
Expires-header with the same content as the Date-header in the
response, so that the document "expires immediately". Don't set
Expires with $r->header_out if you use $r->no_cache, because
header_out takes precedence. the problem that remains are broken
browsers that ignore Expires headers.

Currently to avoid caching alltogether

  my $headers = $r->headers_out;
  $headers->{'Pragma'} = $headers->{'Cache-control'} = 'no-cache';
  $r->no_cache(1);

works with the major browsers.


=head2 2.2) Content related headers

=head2 2.2.1) Content-Type

You are most probably familiar with Content-Type. Sections 3.7,
7.2.1 and 14.17 of the HTTP specs deal with the details.
Mod_perl has the content_type method to deal with this header,
as in

  $r->content_type("image/png");

Content-Type SHOULD be included in all messages according to the
specs, and apache will generate one if you don't. It will be
whatever is specified in the relevant DefaultType configuration
directive or text/plain if none is active.


=head2 2.2.2) Content-Length

The Content-Length header according to the HTTP specs section
14.13, is the number of octets in the body of a message. If it
can be determined prior to sending, it can be very useful for
several reasons to include it. The most important reason why it
is good to include it, is that keepalive requests only work with
responses that contain a Content-Length header. In mod_perl you
can say

  $r->header_out('Content-Length', $length);

If you use Apache::File, you get the additional
set_content_length method for the Apache class which is a bit
more efficient than the above. You can then say:

  $r->set_content_length($length);

The Content-Length header can have an important impact on caches
by invalidating cache entries as the following citation of the
specs explains:

  The response to a HEAD request MAY be cacheable in the sense that the
  information contained in the response MAY be used to update a
  previously cached entity from that resource. If the new field values
  indicate that the cached entity differs from the current entity (as
  would be indicated by a change in Content-Length, Content-MD5, ETag
  or Last-Modified), then the cache MUST treat the cache entry as
  stale.

So be careful to never send a wrong Content-Length, be it in a
GET or in a HEAD request.

=head2 2.2.3) Entity Tags

An Entity Tag is a validator that can be used instead of or in
addition to the Last-Modified header. An entity tag is a quoted
string that has the property to identify different versions of a
particular resource. An entity tag can be added to the response
headers like so:

  $r->header_out("ETag","\"$VERSION\"");

Note: mod_perl offers the Apache::set_etag() method if you have
loaded Apache::File. It is strongly recommended to not use this
method unless you know what you are doing. set_etag() is
expecting that it is used in conjunction with a static request
for a file on disk that has been stat()ed in the course of the
current request. It is inappropriate and dangerous to use it for
dynamic content.

By sending an entity tag you promise to the recipient, that you
will not send the same ETag for the same resource again unless
the content is equal to the one you are sending now (see below
for what equality means).

The pros and cons of using entity tags are discussed in section
13.3 of the HTTP specs. For us mod_perl programmers that
discussion can be summed up as follows:

There are strong and weak validators. Strong validators change
whenever a single bit changes in the response. Weak validators
change when the meaning of the response changes. Strong
validators are needed for caches to allow for sub-range
requests. Weak validators allow a more efficient caching of
equivalent objects. Algorithms like MD5 or SHA are good strong
validators, but what we usually want, when we want to take
advantage of caching, is a good weak validator.

A Last-Modified time, when used as a validator in a request, can
be strong or weak, depending on a couple of rules. Please refer
to section 13.3.3 of the HTTP standard to understand these
rules. This is mostly relevant for range requests as this
citation of section 14.27 explains:

  If the client has no entity tag for an entity, but does have a
  Last-Modified date, it MAY use that date in a If-Range header.

But it is not limited to range requests. Section 13.3.1 succintly
states that

  The Last-Modified entity-header field value is often used as a
  cache validator.

The fact that a Last-Modified date may be used as a strong
validator can be pretty disturbing if we are in fact changing
our output slightly without changing the semantics of the
output. To prevent such kind of misunderstanding between us and
the cache servers in the response chain, we can send a weak
validator in an ETag header. This is possible because the specs
say:

  If a client wishes to perform a sub-range retrieval on a value for
  which it has only a Last-Modified time and no opaque validator, it
  MAY do this only if the Last-Modified time is strong in the sense
  described here.

In other words: by sending them an ETag that is marked as weak
we prevent them to use the Last-Modified header as a strong
validator.

An ETag value is marked as a weak validator by prepending the
string "W/" to the quoted string, otherwise it is strong. In
perl this would mean something like this:

  $r->header_out('ETag',"W/\"$VERSION\"");

Consider carefully, which string you choose to act as a
validator. You are left alone with this decision because...

  ... only the service author knows the semantics of a resource
  well enough to select an appropriate cache validation
  mechanism, and the specification of any validator comparison
  function more complex than byte-equality would open up a can
  of worms. Thus, comparisons of any other headers (except
  Last-Modified, for compatibility with HTTP/1.0) are never used
  for purposes of validating a cache entry.

If you are composing a message from multiple components, it may
be necessary to combine some kind of version information for all
components into a single string.

If you are producing relative big documents or contents that do
not change frequently, you most likely will prefer a strong
entity tag, thus giving caches a chance to transfer the document
in chunks. (Anybody in the mood to add a chapter about ranges to
this document?)

=head2 2.3) Content Negotiation

A particularly wonderful but unfortunately not yet widely
supported feature that was introduced with HTTP 1.1 is content
negotiation. The probably most popular usage scenario of content
negotiation is language negotiation. A user specifies in his
browser preferences the languages he understands and how well he
understands them. The browser includes these settings in an
Accept-Language header when it sends the request to the server
and the server then chooses among several available
representations of the document the one that fits the user's
preferences best. Content negotiation is not limited to
language. Citing the specs:

  HTTP/1.1 includes the following request-header fields for enabling
  server-driven negotiation through description of user agent
  capabilities and user preferences: Accept (section 14.1), Accept-
  Charset (section 14.2), Accept-Encoding (section 14.3), Accept-
  Language (section 14.4), and User-Agent (section 14.43). However, an
  origin server is not limited to these dimensions and MAY vary the
  response based on any aspect of the request, including information
  outside the request-header fields or within extension header fields
  not defined by this specification.

=head2 2.3.1) Vary

In order to signal to the recipient that content negotiation has
been used to determine the best available representation for a
given request, the server must include a Vary header that tells
the recipient, which of the request headers have been used to
determine it. So an answer may be generated like so:

  $r->header_out('Vary', join ", ", 'accept', 'accept-language',
		 'accept-encoding', 'user-agent');

While this may be in the header of a very cool page that greets
the user with something like

  Hallo Kraut, Dein NutScrape versteht zwar PNG aber leider
  kein GZIP.

it has the side effect of being expensive for a caching proxy.
As of this writing, squid (version 2.1PATCH2) does not cache
resources at all that come with a Vary header. So unless you
find a clever workaround, you won't enjoy your squid accelerator
for these documents :-(


=head1 3) Requests

Section 13.11 of the specs states that the only two cachable
methods are GET and HEAD.

=head2 3.1) HEAD

Among the above recommended headers, the date-related ones
(Date, Last-Modified, and Expires/Cache-Control) are usually
easy to produce and thus should be computed for HEAD requests
just the same as for GET requests.

The Content-Type and Content-Length headers should be exactly
the same as would be supplied to the corresponding GET request.
But as it can be expensive to compute them, they can just as
well be omitted, there is nothing in the specs that forces you
to compute them.

What is important for the mod_perl programmer is that the
response to a HEAD request MUST NOT contain a message-body. The
code in your mod_perl handler might look like this:

  # compute all headers that are easy to compute
  if ( $r->header_only ){ # currently equivalent for $r->method eq "HEAD"
    $r->send_http_header;
    return OK;
  }

If you are running a squid accelerator, it will be able to
handle the whole HEAD request for you, but under some
circumstances it may not be allowed to do so.

=head2 3.2) POST

The response to a POST request is not cachable due to an
underspecification in the HTTP standards. Section 13.4 does not forbid
caching of responses to POST request but no other part of the HTTP
standard explains how caching of POST requests could be implemented,
so we are in a vacuum here and all existing caching servers therefore
refuse to implement caching of POST requests. This may change if
somebody does the footwork of defining the semantics for cache
operations on POST. Note that some browsers with their more aggressive
caching do implement caching of POST requests.

Note: If you are running a squid accelerator, you should be aware that
it accelerates outgoing traffic, but does not bundle incoming traffic,
so if you have long post requests, the squid doesn't buy you anything.
So always consider to use a GET instead of a POST if possible.

=head2 3.3) GET

A normal GET is what we usually write our mod_perl programs for.
Nothing special about it. We send our headers followed by the
body.

But there is a certain case that needs a workaround to achieve
better cacheability. We need to deal with the "?" in the
rel_path part of the requested URI. Section 13.9 specifies, that

  ... caches MUST NOT treat responses to such URIs as fresh unless
  the server provides an explicit expiration time. This specifically
  means that responses from HTTP/1.0 servers for such URIs SHOULD NOT
  be taken from a cache.

You're tempted to believe, that we are using HTTP 1.1 and
sending an explicit expiration time, so we're on the safe side?
Unfortunately reality is a little bit different. It has been a
bad habit for quite a long time to misconfigure cache servers
such that they treat all GET requests containing a question mark
as uncacheable. People even used to mark everything as
uncacheable that contained the string "cgi-bin".

To work around this bug in the heads, I have dropped the habit
to call my CGI directories "cgi-bin" and I have written the
following handler that lets me work with CGI-like querystrings
without rewriting the software that deals with them, namely
Apache::Request or CGI.pm.

  sub handler {
    my($r) = @_;
    my $uri = $r->uri;
    if ( my($u1,$u2) = $uri =~ / ^ ([^?]+?) ; ([^?]*) $ /x ) {
      $r->uri($u1);
      $r->args($u2);
    } elsif ( my($u1,$u2) = $uri =~ m/^(.*?)%3[Bb](.*)$/ ) {
      # protect against old proxies that escape volens nolens
      # (see HTTP standard section 5.1.2)
      $r->uri($u1);
      $u2 =~ s/%3B/;/gi;
      $u2 =~ s/%26/;/gi; # &
      $u2 =~ s/%3D/=/gi;
      $r->args($u2);
    }
    DECLINED;
  }

This handler must be installed as a PerlPostReadRequestHandler.

The handler takes any request that contains B<no> questionmark
but one or more semicolons such that the first semicolon is
interpreted as a questionmark and everything after that as the
querystring. You can now exchange the request

  http://foo.com/query?BGCOLOR=blue;FGCOLOR=red

with

  http://foo.com/query;BGCOLOR=blue;FGCOLOR=red

Thus it allows the co-existence of queries from ordinary forms
that are being processed by a browser and predefined requests
for the same resource. It has one minor bug: apache doesn't
allow percent-escaped slashes in such a querystring. So you must
write

  http://foo.com/query;BGCOLOR=blue;FGCOLOR=red;FONT=/font/bla

and must not say

  http://foo.com/query;BGCOLOR=blue;FGCOLOR=red;FONT=%2Ffont%2Fbla


=head2 3.4) Conditional GET

A rather challenging request we mod_perl programmers can get is
the conditional GET, which typically means a request with an
If-Modified-Since header. The HTTP specs have this to say:

  The semantics of the GET method change to a "conditional GET"
  if the request message includes an If-Modified-Since,
  If-Unmodified-Since, If-Match, If-None-Match, or If-Range
  header field. A conditional GET method requests that the
  entity be transferred only under the circumstances described
  by the conditional header field(s). The conditional GET method
  is intended to reduce unnecessary network usage by allowing
  cached entities to be refreshed without requiring multiple
  requests or transferring data already held by the client.

So how can we reduce the unnecessary network usage in such a
case? mod_perl makes it easy for you by offering apache's
meets_conditions(). You have to set up your Last-Modified (and
possibly ETag) header before running this method. If the return
value of this method is anything but OK, you should return from
your handler with that return value and you're done. Apache
handles the rest for you. The following example is taken from
[5]:

  if((my $rc = $r->meets_conditions) != OK) {
     return $rc;
  }
  #else ... go and send the response body ...

If you have a squid accellerator running, it will often handle
the conditionals for you and you can enjoy its extreme fast
responses for such requests by reading the access.log. Just grep
for "TCP_IMS_HIT/304". But as with a HEAD request there are
circumstances under which it may not be allowed to do so. That
is why the origin server (which is the server you're
programming) needs to handle conditional GETs as well even if a
squid accelerator is running.

=head2 3.) Avoiding to deal with them

There is another approach to dynamic content that is possible with
mod_perl.  This approach is appropriate if the content changes
relatively infrequently, if you expect lots of requests to retrieve
the same content before it changes again and if it is much cheaper to
test whether the content needs refreshing than it is to refresh it.

In this case a PerlFixupHandler can be installed for the relevant
location.  It tests whether the content is up to date.  If so it
returns DECLINED and lets the apache core serve the content from a
file.  Otherwise, it regenerates the content into the file, updates
the $r->finfo status and again returns DECLINED so that apache serves
the updated file.  Updating $r->finfo can be achieved by calling

  $r->filename($file); # force update of finfo

even if this seems redundant because the filename is already equal to
$file.  Setting the filename has the side effect of doing a stat() on
the file.  This is important because otherwise apache would use the
out of date finfo when generating the response header.


=head1 References and other literature

 [1] Stas Bekman: Mod_perl Guide. http://perl.apache.org/guide/

 [2] T. Berners-Lee et al.: Hypertext Transfer Protocol --
     HTTP/1.0, RFC 1945.

 [3] R. Fielding et al.: Hypertext Transfer Protocol -- HTTP/1.1, RFC
     2616.

 [4] Martin Hamilton: Cachebusting - cause and prevention,
     draft-hamilton-cachebusting-01. Also available online at
     http://vancouver-webpages.com/CacheNow/

 [5] Lincoln Stein, Doug MacEachern: Writing Apache Modules with
     Perl and C, O'Reilly, 1-56592-567-X. Selected chapters
     available online at http://perl.apache.org. Amazon page at
     http://www.amazon.com/exec/obidos/ASIN/156592567X/writinapachemodu/

=head1 VERSION

You're reading revision $Revision: 1.16 $ of this document,
written on $Date: 1999/08/14 06:21:32 $

=head1 AUTHOR

Andreas Koenig with helpful corrections, addition, comments from
Ask Bjoern Hansen <ask@netcetera.dk>, Frank D. Cringle
<fdc@cliwe.ping.de>, Eric Cholet <cholet@logilune.com>, Mark
Kennedy <mark.kennedy@gs.com>, Doug MacEachern
<dougm@pobox.com>, Tom Hukins <tom@eborcom.com>, Wham Bang
<wham_bang@yahoo.com> and many others.


=cut

