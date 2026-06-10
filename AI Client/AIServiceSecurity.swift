//
//  AIServiceSecurity.swift
//  AI Client
//
//  Created by SharkyMew on 2026/5/20.
//
import Foundation

extension AIService {
    static func makeSecureSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    static func validatedRequestURL(from urlString: String) throws -> URL {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              let host = url.host,
              !host.isEmpty,
              url.user == nil,
              url.password == nil else {
            throw AIServiceError.invalidURL
        }

        if scheme == "https" {
            return url
        }

        if scheme == "http", isLoopbackHost(host) {
            return url
        }

        throw AIServiceError.insecureURL
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let normalizedHost = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
        return normalizedHost == "localhost"
            || normalizedHost == "127.0.0.1"
            || normalizedHost == "::1"
    }
}
