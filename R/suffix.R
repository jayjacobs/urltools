#'@title refresh the stored public suffix dataset
#'
#'@description \code{urltools} comes with an inbuilt
#'dataset of public suffixes, \code{\link{suffix_dataset}}.
#'This is used in \code{\link{suffix_extract}} to identify the top-level domain
#'within a particular domain name.
#'
#'While updates to the dataset will be included in each new package release,
#'there's going to be a gap between changes to TLDs and changes to the package.
#'Accordingly, the package also includes \code{\link{suffix_refresh}}, which refreshes
#'this dataset on the user end. This requires CURL (the library, not the
#'R package) on your system to function.
#'
#'@return TRUE if this worked; an error otherwise.
#'
#'@seealso \code{\link{suffix_extract}} to extract suffixes from domain names,
#'or \code{\link{suffix_dataset}} for the dataset itself.
#'
#'@examples
#'\dontrun{
#'suffix_refresh()
#'}
#'
#'@export
suffix_refresh <- function(){
  
  #Read in and filter
  connection <- url("https://www.publicsuffix.org/list/effective_tld_names.dat", method = "libcurl")
  results <- readLines(connection)
  close(connection)
  suffix_dataset <- results[!grepl(x = results, pattern = "//", fixed = TRUE) & !results == ""]

  #Return the user-friendly version
  save(suffix_dataset, file = system.file("data/suffix_dataset.rda", package = "urltools"))
  return(TRUE)
}

#' @title Dataset of public suffixes
#' @description This dataset contains a registry of public suffixes, as retrieved from
#' and defined by the \href{https://publicsuffix.org/}{public suffix list}. It is
#' sorted by how many periods(".") appear in the suffix, to optimise it for
#' \code{\link{suffix_extract}}.
#'
#' @docType data
#' @keywords datasets
#' @name suffix_dataset
#'
#' @seealso \code{\link{suffix_refresh}} for updating the dataset, and
#' \code{\link{suffix_extract}} for extracting suffixes from domain names.
#'
#' @usage data(suffix_dataset)
#' @note Last updated 2015-05-06.
#' @format A vector of 7430 elements.
NULL

#'@title extract the suffix from domain names
#'@description domain names have suffixes - common endings that people
#'can or could register domains under. This includes things like ".org", but
#'also things like ".edu.co". A simple Top Level Domain list, as a 
#'result, probably won't cut it.
#'
#'\code{\link{suffix_extract}} takes the list of public suffixes,
#'as maintained by Mozilla (see \code{\link{suffix_dataset}}) and
#'a vector of domain names, and produces a data.frame containing the
#'suffix that each domain uses, and the remaining fragment.
#'
#'@param domains a vector of damains, from \code{\link{domain}}
#'or \code{\link{url_parse}}. Alternately, full URLs can be provided
#'and will then be run through \code{\link{domain}} internally.
#'
#'
#'@return a data.frame of two columns, "domain_body" and "suffix".
#'"domain_body" contains that part of the domain name that came
#'before the matched suffix, and the suffix contains..well, the
#'suffix. If a suffix cannot be extracted, \code{domain_body}
#'will contain the entire domain, and \code{suffix} the string
#'"Invalid".
#'
#'@seealso \code{\link{suffix_dataset}} for the dataset of suffixes,
#'and \code{\link{suffix_refresh}} for refreshing it.
#'
#'@examples
#'
#'#Using url_parse
#'domain_name <- url_parse("http://en.wikipedia.org")$domain
#'suffix_extract(domain_name)
#'
#'#Using domain()
#'domain_name <- domain("http://en.wikipedia.org")
#'suffix_extract(domain_name)
#'
#'#Using internal parsing
#'suffix_extract("http://en.wikipedia.org")
#'
#'@export
suffix_extract <- function(domains){
  # grab the reference data set with the TLDs
  suffix_dataset <- urltools::suffix_dataset
  # set up a list of TLD's that have wild card values
  wilds <- grepl('^\\*', suffix_dataset)
  wildcard <- sub('\\*\\.', "", suffix_dataset[wilds])
  # remove them from the TLDs
  static <- suffix_dataset[!wilds]
  
  # set up some blank variables, set length for speed
  subdomain <- domain <- tld <- rep(NA_character_, length(domains))
  # set up a list (one entry per domain) and 
  # split (on dots) the domains into vectors
  splithosts <- strsplit(tolower(domains), "[.]")
  # set the names on the list to sequential value
  # we will use this later to get the index
  names(splithosts) <- seq(length(splithosts))
  # we need to set up how many iterations we have to do 
  # so grab the max length of splits we've done.
  maxlen <- max(sapply(splithosts, length))
  # now loop from 1 to one less of max length 
  # we do one less because we'll never have less 
  # then one field in the TLD (.com, .org, etc.)
  for(split.after in seq(1, maxlen)) {
    # apply through list, 
    templ <- sapply(splithosts, function(x)
      paste0(x[(split.after):length(x)], collapse=".")
    )
    # test if any of of `split.after` match
    matched <- templ %in% static
    # if any of this length matched...
    if (any(matched)) {
      # pull the indexes of those that matched
      # by pulling the names of the entry matched
      index <- as.numeric(names(splithosts)[matched])
      # if we aren't looking at the whole string past in
      if (split.after>1) { # then we have a domain
        # save off the domain
        domain[index] <- sapply(splithosts[matched], function(x) unlist(x[split.after-1]))
        if (split.after>2) { # then we have a subdomain
          # and if we are at least 2 in, we have a subdomain 
          subdomain[index] <- sapply(splithosts[matched], function(x) paste(x[1:(split.after-2)], collapse="."))
        }
      }
      # save the matched entities off into the tld vectors
      tld[index] <- sapply(splithosts[matched], function(x) paste(x[(split.after):length(x)], collapse="."))
      
    }
    # now the wildcard lookups, same concept as above
    matched2 <- templ %in% wildcard
    if (any(matched2) && split.after > 1) {
      safter <-  split.after - 1
      index <- as.numeric(names(splithosts)[matched2])
      if (safter>1) {
        domain[index] <- sapply(splithosts[matched2], function(x) x[safter-1])
        if (safter>2) {
          subdomain[index] <- sapply(splithosts[matched2], function(x) paste(x[1:(safter-2)], collapse="."))
        }
      }
      tld[index] <- sapply(splithosts[matched2], function(x) paste(x[(safter):length(x)], collapse="."))
    }
    # now this is where it gets fun
    # if we matched anything,
    # remove those from the splithosts data 
    if (any(matched2 | matched)) {
      splithosts <- splithosts[!(matched | matched2)]
      if(length(splithosts)<1) break
    }
  }
  data.frame(host=domains, subdomain=subdomain, domain=domain, suffix=tld, stringsAsFactors = FALSE)
}