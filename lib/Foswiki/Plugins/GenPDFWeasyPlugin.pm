# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2015-2019 Michael Daum http://michaeldaumconsulting.com
#
# This license applies to GenPDFPrincePlugin *and also to any derivatives*
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::GenPDFWeasyPlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Sandbox ();
use File::Path ();
use Encode ();
use File::Temp ();

our $VERSION = '2.01';
our $RELEASE = '12 Nov 2019';
our $SHORTDESCRIPTION = 'Generate PDF using <nop>WeasyPrint';
our $NO_PREFS_IN_TOPIC = 1;

use constant TRACE => 0; # toggle me

###############################################################################
sub writeDebug {
  print STDERR "GenPDFWeasyPlugin - $_[0]\n" if TRACE;
}

###############################################################################
sub initPlugin {

  if ($Foswiki::Plugins::VERSION < 2.0) {
    Foswiki::Func::writeWarning('Version mismatch between ',
    __PACKAGE__, ' and Plugins.pm');
    return 0;
  }

  my $query = Foswiki::Func::getCgiQuery();
  my $contenttype = $query->param("contenttype") || 'text/html';
  my $context = Foswiki::Func::getContext();

  if ($contenttype eq "application/pdf") {
    $context->{genpdf_doit} = 1;
    $context->{static} = 1;
  } else {
    $context->{genpdf_doit} = 0;
  }

  return 1;
}

###############################################################################
sub completePageHandler {
  #my($html, $httpHeaders) = @_;

  my $context = Foswiki::Func::getContext();
  my $session = $Foswiki::Plugins::SESSION;
  my $baseWeb = $session->{webName};
  my $baseTopic = $session->{topicName};

  return unless $context->{genpdf_doit};

  my $siteCharSet = $Foswiki::cfg{Site}{CharSet};

  my $content = $_[0];

  # remove left-overs and some basic clean-up
  $content =~ s/([\t ]?)[ \t]*<\/?(nop|noautolink)\/?>/$1/gis;
  $content =~ s/<!--.*?-->//g;
  $content =~ s/[\0-\x08\x0B\x0C\x0E-\x1F\x7F]+/ /g;
  $content =~ s/(<\/html>).*?$/$1/gs;
  $content =~ s/^\s*$//gms;

  # clean up toc links
  #$content =~ s/<a href="\?.*?#/<a href="#/g;

  # remove base
  #$content =~ s/<base.*//;

  # clean url params in anchors 
  $content =~ s/(href=["'])\?.*(#[^"'\s])+/$1$2/g;

  # rewrite some urls to use file://..
  $content =~ s/(<link[^>]+href=["'])([^"']+)(["'])/$1.toFileUrl($2).$3/ge;
  $content =~ s/(<img[^>]+src=["'])([^"']+)(["'])/$1.toFileUrl($2).$3/ge;

  # create temp files
  my $htmlFile = new File::Temp(SUFFIX => '.html', UNLINK => (TRACE ? 0 : 1));

  # create output filename
  my ($pdfFilePath, $pdfFile) = getFileName($baseWeb, $baseTopic);

  # convert to utf8
  $content = Encode::decode($siteCharSet, $content) unless $Foswiki::UNICODE;
  $content = Encode::encode_utf8($content);

  # creater html file
  binmode($htmlFile);
  print $htmlFile $content;
  writeDebug("htmlFile=" . $htmlFile->filename);

  # create print command
  my $pubUrl = getPubUrl();
  my $cmd = $Foswiki::cfg{GenPDFWeasyPlugin}{WeasyCmd}
    || '/usr/local/bin/weasyprint --base-url %BASEURL|U% --media-type print --encoding utf-8 %INFILE|F% %OUTFILE|F%';

  writeDebug("cmd=$cmd");
  writeDebug("BASEURL=$pubUrl");

  # execute
  my ($output, $exit, $error) = Foswiki::Sandbox->sysCommand(
    $cmd,
    BASEURL => $pubUrl,
    OUTFILE => $pdfFilePath,
    INFILE => $htmlFile->filename,
  );

  local $/ = undef;

  writeDebug("htmlFile=" . $htmlFile->filename);
  writeDebug("output=$output");
  writeDebug("exit=$exit");
  writeDebug("error=$error");

  if ($exit) {
    throw Error::Simple("execution of weasy failed ($exit) \n\n$error");
  }

  my $query = Foswiki::Func::getCgiQuery();
  if (($query->param("pdfdisposition") || '') eq 'inline') {
    my $pdf = readFile($pdfFilePath);
    $session->{response}->body($pdf);

    # SMELL: prevent compression
    $ENV{'HTTP_ACCEPT_ENCODING'} = ''; 
    $ENV{'HTTP2'} = ''; 
  } else {
    my $url = $Foswiki::cfg{PubUrlPath} . '/' . $baseWeb . '/' . $baseTopic . '/' . $pdfFile . '?t=' . time();
    writeDebug("redirecting to $url");
    Foswiki::Func::redirectCgiQuery($query, $url);
  }

  $_[0] = ""; # don't send back anything else
}

###############################################################################
sub getFileName {
  my ($web, $topic) = @_;

  my $query = Foswiki::Func::getCgiQuery();
  my $fileName = $query->param("outfile") || 'genpdf_'.$topic.'.pdf';

  $fileName =~ s{[\\/]+$}{};
  $fileName =~ s!^.*[\\/]!!;
  $fileName =~ s/$Foswiki::regex{filenameInvalidCharRegex}//go;

  $web =~ s/\./\//g;
  my $filePath = Foswiki::Func::getPubDir().'/'.$web.'/'.$topic;
  File::Path::mkpath($filePath);

  $filePath .= '/'.$fileName;

  return ($filePath, $fileName);
}

###############################################################################
sub toFileUrl {
  my $url = shift;

  my $fileUrl = $url;
  my $localServerPattern = '^(?:'.$Foswiki::cfg{DefaultUrlHost}.')?'.$Foswiki::cfg{PubUrlPath}.'(.*)$';
  $localServerPattern =~ s/https?/https?/;

  if ($fileUrl =~ /$localServerPattern/) {
    $fileUrl = $1;
    $fileUrl =~ s/\?.*$//;
    $fileUrl = "file://".$Foswiki::cfg{PubDir}.$fileUrl;
  } else {
    #writeDebug("url=$url does not point to a local asset (pattern=$localServerPattern)");
  }

  #writeDebug("url=$url, fileUrl=$fileUrl");
  return $fileUrl;
}

###############################################################################
sub modifyHeaderHandler {
  my ($hopts, $request) = @_;

  my $session = $Foswiki::Plugins::SESSION;
  my $baseWeb = $session->{webName};
  my $baseTopic = $session->{topicName};
  my $context = Foswiki::Func::getContext();

  $hopts->{'Content-Disposition'} = "inline;filename=$baseTopic.pdf" if $context->{genpdf_doit};
}

###############################################################################
sub getPubUrl {
  my $session = $Foswiki::Plugins::SESSION;

  if ($session->can("getPubUrl")) {
    # pre 2.0
    return $session->getPubUrl(1);
  } 

  # post 2.0
  return Foswiki::Func::getPubUrlPath(undef, undef, undef, absolute=>1);
}

###############################################################################
sub readFile {
  my $name = shift;
  my $data = '';
  my $IN_FILE;

  open($IN_FILE, '<', $name) || return '';
  binmode $IN_FILE;

  local $/ = undef;    # set to read to EOF
  $data = <$IN_FILE>;
  close($IN_FILE);

  $data = '' unless $data;    # no undefined
  return $data;
}

1;
