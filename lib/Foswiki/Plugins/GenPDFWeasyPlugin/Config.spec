# ---+ Extensions
# ---++ GenPDFWeasyPlugin
# **PATH**
# weasyprint executable 
$Foswiki::cfg{GenPDFWeasyPlugin}{WeasyCmd} = '/usr/local/bin/weasyprint --optimize-images --base-url %BASEURL|U% --media-type print --encoding utf-8 %INFILE|F% %OUTFILE|F%';

1;
