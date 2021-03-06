#!/usr/bin/env Rscript
## Read minimap .paf files and generate a-v-a dotplots

## * minimap OUTPUT FORMAT
##
## Minimap outputs mapping positions in the Pairwise mApping Format (PAF). PAF
## is a TAB-delimited text format with each line consisting of at least 12
## fields as are described in the following table:
##
## ┌────┬────────┬─────────────────────────────────────────────────────────────┐
## │Col │  Type  │                         Description                         │
## ├────┼────────┼─────────────────────────────────────────────────────────────┤
## │  1 │ string │ Query sequence name                                         │
## │  2 │  int   │ Query sequence length                                       │
## │  3 │  int   │ Query start coordinate (0-based)                            │
## │  4 │  int   │ Query end coordinate (0-based)                              │
## │  5 │  char  │ `+' if query and target on the same strand; `-' if opposite │
## │  6 │ string │ Target sequence name                                        │
## │  7 │  int   │ Target sequence length                                      │
## │  8 │  int   │ Target start coordinate on the original strand              │
## │  9 │  int   │ Target end coordinate on the original strand                │
## │ 10 │  int   │ Number of matching bases in the mapping                     │
## │ 11 │  int   │ Number bases, including gaps, in the mapping                │
## │ 12 │  int   │ Mapping quality (0-255 with 255 for missing)                │
## └────┴────────┴─────────────────────────────────────────────────────────────┘

library(ggplot2)
library(scales)
library(stringr)
library(argparse)
library(proto)

## * aux
humanize_format <- function(...) {
    function(x) humanize(x, ...)
}

humanize <- function(x, digits=2, sep=" ", unit="bp"){
  pre <- c("","k","M","G","T");
  px <- as.integer(ifelse(x > 0, log10(x)/3, 0))
  v <- signif(x/(10^(px*3)), digits=digits)
  pre[!pre==''] <- paste(sep, pre[!pre==''], sep='')
  return(paste(v, pre[px+1], unit, sep=""))
}


## * read args/input
ARGPARSE_TRUE <- TRUE
parser <- ArgumentParser()

## ** dryrun some args - allows interface with bash master script
args.cmd <- commandArgs(TRUE)
if (args.cmd[1] == "--argparse"){
    ARGPARSE_TRUE <- "" # FALSE does not work - argparse bug
    args.cmd <- args.cmd[-1]
}

## ** argparse

## -s (hort), --long ...
parser$add_argument("-i", required=ARGPARSE_TRUE, metavar="PAF", help="supported formats: paf")
parser$add_argument("-l", required=ARGPARSE_TRUE, metavar="LEN", help="per set sequence lengths")
parser$add_argument("-o", metavar="OUT", default="minidot.pdf", help="output file, .pdf/.png")
parser$add_argument("-S", "--no-self", action="store_true", default=FALSE, help="exclude plots of set against itself")
parser$add_argument("--strip", action="store_true", default=FALSE, help="remove facets, axes and junk")
parser$add_argument("--title", help="plot title")
parser$add_argument("--theme", default="dark", help="themes: dark, light. [dark]")
parser$add_argument("--width", default=20, help="plot width (cm)", type="double")
parser$add_argument("--thick", default=2, help="line thickness (px)", type="double")
parser$add_argument("--identity", default=0, help="minimum identity (0.0 - 1.0)", type="double")
parser$add_argument("--alen", default=0, help="minimum alignment length", type="double")


args <- parser$parse_args(args.cmd)

if (ARGPARSE_TRUE == "") quit();

## debug
#setwd("/home/thackl/projects/coding/sandbox/R-minimap-dotplots")
#args <- c("minidot.paf", "minidot.len");

## * read paf and len
paf <- read.table(args$i, fill=TRUE, header=FALSE)
len <- read.table(args$l) #, stringAsFactor=FALSE)


paf$ava <- paf$V1:paf$V6
paf$strand <- ifelse(paf$V5=='+', 1, -1)
paf[paf$strand==-1,8:9] <- paf[paf$strand==-1,9:8]


#paf$idy <- paf$V10 / paf$V11 * paf$strand   # minimap1
paf$idy <- gsub("dv:f:","",paf$V16) # gross workaround for using est. divergence from minimap2 dv tag
paf$idy <- (1.0 - as.numeric(paf$idy)) * paf$strand

# Drop sequences lower than the absolute identity
paf <- paf[abs(paf$idy) >= args$identity,]

# Drop sequences shorter than alen
paf <- paf[abs(paf$V4-paf$V3) >= args$alen,]

## * map contig boundaries to gglayer

len.cum <- cbind(len, cumsum=c(lapply(split(len, len$V1),
               function(x) cumsum(x$V2)), recursive=T))
yava <- data.frame(V1=character(0), V6=character(0), yi=numeric(0))
ava.se <- data.frame(V1=character(0), V6=character(0), x=numeric(0), xend=numeric(0), y=numeric(0), yend=numeric(0))
xava <- data.frame(V1=character(0), V6=character(0), xi=numeric(0))
yava.rt <- data.frame(V1=character(0), V6=character(0), xmin=numeric(0), xmax=numeric(0), ymin=numeric(0), ymax=numeric(0))
xava.rt <- data.frame(V1=character(0), V6=character(0), xmin=numeric(0), xmax=numeric(0), ymin=numeric(0), ymax=numeric(0))

ava.bg <- data.frame(V1=character(0), V6=character(0), xmin=numeric(0), xmax=numeric(0), ymin=numeric(0), ymax=numeric(0))

if(args$no_self){
    paf<-paf[!paf$V1==paf$V6,]
    paf<-paf[paf$V1==paf$V1[1],]
}


for(i in unique(paf$ava)){
    r <- str_split_fixed(i, ":", 2)
    yi <- c(0,len.cum$cumsum[len.cum$V1==r[2]])
    yi.max <- yi[length(yi)]
    xi <- c(0,len.cum$cumsum[len.cum$V1==r[1]])
    xi.max <- xi[length(xi)]

    ava.bg <- rbind(ava.bg, data.frame(V1=r[1], V6=r[2],
                         xmin=xi.max * -0.01, xmax=xi.max*1.01,
                         ymin=yi.max * -0.01, ymax=yi.max*1.01))

    ava.se <- rbind(ava.se, data.frame(V1=r[1], V6=r[2],  y=yi, yend=yi, x=0, xend=xi.max))
    ava.se <- rbind(ava.se, data.frame(V1=r[1], V6=r[2],  y=0, yend=yi.max, x=xi, xend=xi))
}

## * plot

gg <- ggplot(paf)
#gg <- gg + geom_rect(data=xava.rt, aes(xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax), fill="green", alpha=0.5)
#gg <- gg + geom_rect(data=yava.rt, aes(xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax), fill="red", alpha=0.5)

if (args$theme=="dark"){
    col.fill <- "grey20"
    col.line <- "grey50"
}else if (args$theme=="light"){
    col.fill <- "white"
    col.line <- "grey20"
}

gg <- gg + geom_rect(data=ava.bg, aes(xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax), fill=col.fill)
#gg <- gg + geom_segment(data=ava.se, aes(x=x,xend=xend,y=y,yend=yend), size=.1, color=col.line, linetype = 3) # ignore contig lines
gg <- gg + geom_segment(data=paf, aes(x=V3, xend=V4, y=V8, yend=V9, color=idy), size=args$thick, lineend = "round")

if (args$theme=="dark") gg <- gg + scale_colour_distiller("Identity", palette="Spectral", direction=1, limits=c(-1, 1))
if (args$theme=="light") gg <- gg + scale_colour_gradientn("Identity", colours = c("#d60004", "#e8ae00", "#666666", "#666666", "#19bf5e", "#1701d2"), limits=c(-1, 1))

gg <- gg + theme(
    panel.grid.major = element_blank(),
    panel.grid.minor = element_blank(),
    panel.background = element_rect(fill = "white"),
    axis.title.x=element_blank(),
    axis.title.y=element_blank()
)

gg <- gg + scale_x_continuous(label=humanize_format(unit='',sep=''), expand=c(0,0), limits=c(-1,max(c(ava.bg$xmax, ava.bg$ymax)) ))
gg <- gg + scale_y_continuous(label=humanize_format(unit='',sep=''), expand=c(0,0), limits=c(-1,max(c(ava.bg$xmax, ava.bg$ymax)) ))
gg <- gg + facet_grid(V6~V1, drop=TRUE, as.table=FALSE)

if(args$strip){
    gg <- gg + theme(legend.position="none")
    gg <- gg + theme(strip.background = element_blank(), strip.text.x = element_blank(), strip.text.y = element_blank(), axis.text.x=element_blank(), axis.text.y=element_blank())
}

if (!is.null(args$title)) gg <- gg + ggtitle(args$title)
ggsave(args$o, plot=gg, width=args$width, height=args$width, units="cm")
