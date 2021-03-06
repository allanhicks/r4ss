#' Calculate new tunings for length and age compositions
#'
#' Creates a table of values that can be copied into the SS control file
#' for SS 3.30 models to adjust the input sample sizes for length and age
#' compositions based on either the Francis or McAllister-Ianelli tuning.
#'
#' Note: starting with SS version 3.30.12, the "Length_Comp_Fit_Summary"
#' table in Report.sso is already in the format required to paste into
#' the control file to apply the McAllister-Ianelli tuning. However, this
#' function provides the additional option of the Francis tuning and the
#' ability to compare the two approaches.  Also note, that the
#' Dirichlet-Multinomial likelihood is an alternative approach that allow
#' the tuning factor to be estimated rather than iteratively tuned.
#'
#' @param replist List output from SS_output
#' @param fleets Either the string 'all', or a vector of fleet numbers
#' @param option Which type of tuning: 'none', 'Francis', or 'MI'
#' @param digits Number of digits to round numbers to
#' @param write Write suggested tunings to a file 'suggested_tunings.ss'
#'
#' @return Returns a table that can be copied into the control file.
#' If \code{write=TRUE} then will write the values to a file
#' (currently hardwired to go in the directory where the model was run
#' and called "suggested_tunings.ss")
#'
#' @author Ian G. Taylor
#' @export
#' @seealso \code{\link{SSMethod.TA1.8}}
#' @references Francis, R.I.C.C. (2011). Data weighting in statistical
#' fisheries stock assessment models. Can. J. Fish. Aquat. Sci. 68: 1124-1138.
SS_tune_comps <- function(replist, fleets='all', option="Francis",
                          digits=6, write=TRUE){
  # check inputs
  if(!option %in% c("none", "Francis", "MI")){
    stop("Input 'option' should be 'none', 'Francis', or 'MI'")
  }
  if(fleets[1]=="all"){
    fleets <- 1:replist$nfleets
  }else{
    if(length(intersect(fleets,1:replist$nfleets))!=length(fleets)){
      stop("Input 'fleets' should be 'all' or a vector of fleet numbers.")
    }
  }

  # place to store info on data weighting
  tuning_table <- data.frame(Factor       = integer(),
                             Fleet        = integer(),
                             Var_adj      = double(),
                             Hash         = character(),
                             Old_Var_adj  = double(),
                             New_Francis  = double(),
                             New_MI       = double(),
                             Francis_mult = double(),
                             Francis_lo   = double(),
                             Francis_hi   = double(),
                             MI_mult      = double(),
                             Type         = character(),
                             Name         = character(),
                             Note         = character(),
                             stringsAsFactors=FALSE)

  # loop over fleets and modify the values for length data
  for(type in c("len","age")){
    for(fleet in fleets){
      cat("calculating",type,"tunings for fleet",fleet,"\n")
      if(type=="len"){
        # table of info from SS
        tunetable <- replist$Length_comp_Eff_N_tuning_check
        Factor <- 4 # code for Control file
        has_marginal <- fleet %in% replist$lendbase$Fleet
        has_conditional <- FALSE
      }
      if(type=="age"){
        # table of info from SS
        tunetable <- replist$Age_comp_Eff_N_tuning_check
        Factor <- 5 # code for Control file
        has_marginal <- fleet %in% replist$agedbase$Fleet
        has_conditional <- fleet %in% replist$condbase$Fleet
      }
      if(has_marginal & has_conditional){
        warning("fleet", fleet, "has both conditional ages and marginal ages",
                "\ntuning will be based on conditional ages")
      }
      if(has_marginal | has_conditional){
        # data is present, calculate stuff
        # Francis_multiplier
        Francis_mult <- NULL
        Francis_lo <- NULL
        Francis_hi <- NULL
        Francis_output <- SSMethod.TA1.8(fit=replist, type=type,
                                         fleet=fleet, plotit=FALSE)
        if(has_conditional){
          # run separate function for conditional data
          # (replaces marginal multiplier if present)
          Francis_output <- SSMethod.Cond.TA1.8(fit=replist,
                                                fleet=fleet, plotit=FALSE)          
        }
        Francis_mult <- Francis_output[1]
        Francis_lo <- Francis_output[2]
        Francis_hi <- Francis_output[3]
        Note <- ""
        if(is.null(Francis_output)){
          Francis_mult <- NA
          Francis_lo <- NA
          Francis_hi <- NA
          Note <- "No Francis weight"
        }
        # current value
        Curr_Var_Adj <- NA
        if("Curr_Var_Adj" %in% names(tunetable)){
          Curr_Var_Adj <- tunetable$Curr_Var_Adj[tunetable$Fleet==fleet]
        }
        if("Var_Adj" %in% names(tunetable)){
          Curr_Var_Adj <- tunetable$Var_Adj[tunetable$Fleet==fleet]
        }
        if(is.na(Curr_Var_Adj)){
          stop("Model output missing required values, perhaps due to an older version of SS")
        }

        # McAllister-Ianelli multiplier
        MI_mult <- NA
        if("HarMean(effN)/mean(inputN*Adj)" %in% names(tunetable)){
          MI_mult <- tunetable$"HarMean(effN)/mean(inputN*Adj)"[tunetable$Fleet==fleet]
        }
        if("MeaneffN/MeaninputN" %in% names(tunetable)){
          MI_mult <- tunetable$"MeaneffN/MeaninputN"[tunetable$Fleet==fleet]
        }
        if("Factor" %in% names(tunetable)){
          # starting with version 3.30.12
          MI_mult <- tunetable$Recommend_var_adj[tunetable$Fleet==fleet] /
            tunetable$Curr_Var_Adj[tunetable$Fleet==fleet]
        }
        if(is.na(MI_mult)){
          stop("Model output missing required values, perhaps due to an older version of SS")
        }

        # make new row for table
        newrow <-
          data.frame(Factor       = Factor,
                     Fleet        = fleet,
                     New_Var_adj  = NA,
                     hash         = "#",
                     Old_Var_adj  = round(Curr_Var_Adj, digits),
                     New_Francis  = round(Curr_Var_Adj*Francis_mult, digits),
                     New_MI       = round(Curr_Var_Adj*MI_mult, digits),
                     Francis_mult = round(Francis_mult, digits),
                     Francis_lo   = round(Francis_lo, digits),
                     Francis_hi   = round(Francis_hi, digits),
                     MI_mult      = round(MI_mult, digits),
                     Type         = type,
                     Name         = replist$FleetNames[fleet],
                     Note         = Note,
                     stringsAsFactors=FALSE)
        
        # add row to existing table
        tuning_table <- rbind(tuning_table, newrow)
        
      } # end check for data type for this fleet
    } # end loop over fleets
  } # end loop over length or age

  # fill in new variance adjustment based on chosen option
  if(option=="none"){
    tuning_table$New_Var_adj <- tuning_table$Old_Var_adj
  }
  if(option=="Francis"){
    tuning_table$New_Var_adj <- tuning_table$New_Francis
    NAvals <- is.na(tuning_table$New_Var_adj)
    tuning_table$New_Var_adj[NAvals] <- tuning_table$New_MI[NAvals]
    tuning_table$Note[NAvals] <- paste0(tuning_table$Note[NAvals], "--using MI value")
  }
  if(option=="MI"){
    tuning_table$New_Var_adj <- tuning_table$New_MI
  }
  names(tuning_table)[1] <- "#Factor" # add hash to facilitate pasting into Control
  rownames(tuning_table) <- 1:nrow(tuning_table)

  # stuff related to generalized size frequency data
  tunetable_size <- replist$Size_comp_Eff_N_tuning_check
  if(!is.null(tunetable_size)){
    warning("\n  Generalized size composition data doesn't have\n",
            "  Francis weighting available and the table of tunings\n",
            "  is formatted differently in both 'suggested_tuning.ss'\n",
            "  and the data.frame returned by this function\n",
            "  (which are also formatted different from each other).")
  }
  
  # return the results
  if(write){
    file <- file.path(replist$inputs$dir, "suggested_tuning.ss")
    cat("writing to file", file, "\n")
    write.table(tuning_table,
                file=file, quote=FALSE, row.names=FALSE)
    # append generalized size comp table with different columns
    if(!is.null(tunetable_size)){
      names(tunetable_size)[1] <- "#Factor" # add hash to facilitate pasting into Control
      write.table(tunetable_size,
                  file=file, quote=FALSE, row.names=FALSE, append=TRUE)
    }
  }
  # remove mismatched columns from generalized size comp data to combine
  # with other data types
  if(!is.null(tunetable_size)){
    tunetable_size[,-(1:4)] <- NA
    names(tunetable_size) <- names(tuning_table)
    tuning_table <- rbind(tuning_table, tunetable_size)
  }
  # return the table
  return(tuning_table)
}
