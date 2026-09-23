variable "functions" {
  type = map(object({
    name = string
    source_dir = string
    output_dir = string
    route_key = string
  }))
  default = {
    "book" = {
      name = "book-lambda-function",
      source_dir = "book",
      output_dir = "book.zip"
      route_key = "GET /book"
    },
    "user" = {
      name = "user-lambda-function",
      source_dir = "user",
      output_dir = "user.zip",
      route_key = "GET /user/{id+}" 
      # this matches requests with "/user/nepal/fdfd" "/user/africa/dsds"
    }
  }
}