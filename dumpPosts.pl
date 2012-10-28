#!/usr/bin/perl

use strict;
use warnings;
use Encode;

use LWP::UserAgent;
use HTTP::Request;
use HTML::TreeBuilder;
use Date::Language;
use Redis;

my $url = "http://habrahabr.ru/posts/collective/all/";

my $redis = Redis->new;
my $tree;

open(FILE, ">file.html");
print FILE '
<html><head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8"></head>
<body>';

$tree = getTree($url);
for my $a ($tree->look_down(class => "post_title")) {
	my $href = normalize($a->attr("href"));
	my $title = normalize($a->as_text);

	my %postData = getPostData($href);
	print $href . " -- " . $postData{"published"} . "\n";

	print FILE ($title."<br />".$postData{"html_post"}."<hr>");
}

print FILE '</body></html>';

sub getPostData {
	my $url = shift;
	my %ret;
	my $postTree = getTree($url);
	my $htmlPost = $postTree->look_down(class => "content html_format");
	if ($htmlPost) {
		$ret{"status"} = "live";
		$ret{"html_post"} = normalize($htmlPost->as_HTML);
		my $pubDate = $postTree->look_down(class => "published");
		$ret{"published"} = getUnixDate(normalize($pubDate->as_text));
	} else {
		my @piss = $postTree->look_down(_tag => "p");
		if ($piss[1]) {
			normalize($piss[1]->as_text) =~ /^Автор переместил топик в черновики.$/ ? $ret{"status"} = "draft" : $ret{"status"} = "undef";
		} else {
			$ret{"status"} = "error"
		}
	}
	return %ret;
}

sub normalize {
	my $str = shift;
	HTML::Entities::decode_entities($str);
	utf8::encode($str);
	return $str;
}

sub getTree {
	my $url = shift;
	my $ua = LWP::UserAgent->new;
	my $req = HTTP::Request->new(GET=>$url);
	my $resp = $ua->request($req);
	my $tree = HTML::TreeBuilder->new;

	return $tree->parse_content(Encode::decode_utf8 $resp->content);
}

sub getUnixDate {
	my $dirtyDate = shift;
	my $ret;

	my $lang = Date::Language->new('Russian');
	my $firstPart;
	if($dirtyDate =~ /^сегодня/) {
		$firstPart = Encode::decode("koi8-r", $lang->time2str("%d %B %Y",time));
	} elsif ($dirtyDate =~ /^вчера/) {
		$firstPart = Encode::decode("koi8-r", $lang->time2str("%d %B %Y",time-86400));
	} else {
		$dirtyDate =~ /^(.+) в /;
		$firstPart = $1;

		# TODO: its realy dirty, rework later
		$firstPart =~ /\s(\w)/;
		my $uc = uc $1;
		$firstPart =~ s/\s\w/ $uc/g;
	}
	$dirtyDate =~ /(\d\d):(\d\d)$/;
	$ret = "$firstPart $1:$2";
	$ret = $lang->str2time(Encode::encode("koi8-r", $ret));
	return $ret;
}