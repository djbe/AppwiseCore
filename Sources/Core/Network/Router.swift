//
// AppwiseCore
// Copyright © 2021 Appwise
//

import Alamofire

public typealias MultipartBuilder = (MultipartFormData) -> Void

/// This protocol represents the elements needed to create an URL request, usually in combination
/// with a network client. The implementation for a router is usually an enum.
public protocol Router: URLRequestConvertible, URLConvertible {
	/// The base url for this router, all paths will be relative to this url.
	static var baseURLString: String { get }

	/// The HTTP method (get, post, ...). Optional, default: .get
	var method: HTTPMethod { get }

	/// The path relative to the base URL. Required
	var path: String { get }

	/// The request headers (dictionary). Optional, default: empty dictionary
	var headers: [String: String] { get }

	/// The parameters for a request, will be encoded using the `encoding`. Optional, default: nil
	var params: Parameters? { get }

	/// The parameters for a request, will be encoded using the `encoding`. Optional, default: nil
	var anyParams: Any? { get }

	/// The encoding to apply to the parameters. Optional, default: `JSONEncoding`
	var encoding: ParameterEncoding { get }

	/// The closure to build multipart components if needed. Optional, default: nil
	var multipart: MultipartBuilder? { get }

	/// The update interval that should be applied to this request. Optional, default: 1 day
	var updateInterval: TimeInterval { get }
}

// MARK: - URLConvertible

public extension Router {
	func asURL() throws -> URL {
		let baseURL = try Self.baseURLString.asURL()
		guard let url = URL(string: path, relativeTo: baseURL) else {
			throw AFError.invalidURL(url: path)
		}

		return url
	}
}

// MARK: - URLRequestConvertible

public extension Router {
	func asURLRequest() throws -> URLRequest {
		precondition(multipart == nil, "Cannot build request, it has a multipart constructor. Please use `asURLRequest(with:completion:)`")

		return try buildURLRequest()
	}

	/// Asynchronously build a data request for this route. This is recommended in case you
	/// have a large amount of multipart data that gets added in the `multipart` closure.
	///
	/// - parameter sessionManager: The session manager used to construct the data request
	/// - parameter completion: The completion closure to call when finished
	/// - parameter result: The resulting data request (or an error)
	func asURLRequest(with sessionManager: SessionManager, completion: @escaping (_ result: Swift.Result<DataRequest, Error>) -> Void) {
		let request: URLRequest
		do {
			request = try buildURLRequest()
		} catch {
			return completion(.failure(error))
		}

		if let multipart = multipart {
			sessionManager.upload(multipartFormData: multipart, with: request) { result in
				switch result {
				case .success(let request, _, _):
					completion(.success(request))
				case .failure(let error):
					completion(.failure(error))
				}
			}
		} else {
			let dataRequest = sessionManager.request(request)
			completion(.success(dataRequest))
		}
	}

	private func buildURLRequest() throws -> URLRequest {
		let params = self.params ?? anyParams

		var request = try URLRequest(url: self, method: method, headers: headers)
		if let encoding = encoding as? JSONEncoding {
			request = try encoding.encode(request, withJSONObject: params)
		} else if let params = params as? Parameters {
			request = try encoding.encode(request, with: params)
		} else if params != nil {
			preconditionFailure("Cannot encode non-dictionary when Router encoding is not JSON")
		}

		return request
	}
}

// MARK: - Default implementation

public extension Router {
	var method: HTTPMethod {
		.get
	}

	var headers: [String: String] {
		[:]
	}

	var params: Parameters? {
		nil
	}

	var anyParams: Any? {
		nil
	}

	var encoding: ParameterEncoding {
		JSONEncoding.default
	}

	var multipart: MultipartBuilder? {
		nil
	}
}

public extension Router {
	/// Default update interval is 1 day
	var updateInterval: TimeInterval {
		24 * 3_600
	}

	/// When the request was last performed (defaults to timestamp 0)
	var lastUpdated: TimeInterval {
		Settings.shared.timestamp(router: self)
	}

	/// Checks wether a resource should be updated
	///
	/// - parameter completion: The completion block to call when you have the update related information
	/// - parameter resource: The router item to check for information
	/// - parameter shouldUpdate: True if the resource should be updated or not
	func shouldUpdate(completion: (_ resource: Self, _ shouldUpdate: Bool) -> Void) {
		let now = Date().timeIntervalSince1970

		// should update if more than 1 day ago
		let should = now - Settings.shared.timestamp(router: self) > updateInterval
		completion(self, should)
	}

	/// Set the last updated timestamp for this resource
	///
	/// - parameter timestamp: The date to set the timestamp to. Defaults to now.
	func touch(_ timestamp: Date = Date()) {
		Settings.shared.setTimestamp(timestamp.timeIntervalSince1970, router: self)
	}
}
