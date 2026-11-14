import Foundation

enum MuseumAPIError: Error {
    case invalidResponse
    case http(Int)
}
