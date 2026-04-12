EnsureColumn <- function(data, columnName, insertValue = NA) {
  if (!(columnName %in% colnames(data))) {
    data[[columnName]] <- insertValue
  }
  return(data)
}
