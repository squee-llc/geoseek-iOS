//
//  NetworkingController.swift
//  GeoSeek
//
//  Created by morse on 2/25/20.
//  Copyright © 2020 Brandi Bailey. All rights reserved.
//

import Foundation

enum FetchError: String, Error {
    case badData = "There was a data error. Please try again." // TODO Fix error messages
    case badResponse = "There was a bad response. Please try again."
    case badEncode = "There was a problem encoding. Please try again."
    case otherError = "Something went wrong. Please try again."
}

enum HTTPMethod: String {
    case get = "GET"
    case put = "PUT"
    case post = "POST"
    case delete = "DELETE"
}

enum UserAction: String {
    case login = "login"
    case register = "register"
}

class NetworkController {
    
    // MARK: - Properties
    
    static let shared = NetworkController()
    private let baseURL = "https://geoseek-be-stage.herokuapp.com/api/"
    
    // MARK: - Lifecycle Methods
    
    private init() {}
    
    // MARK: - Gems
    
    func fetchGems(completion: @escaping (Result<[Gem], FetchError>) -> Void) {
        let request = gemsURL(with: .get)
        
        perform(request) { result in
            switch result {
            case .failure(let error):
                completion(.failure(.badData))
                print("NetworkController.fetchGems:", error)
            case .success(let data):
                let possibleGems: [GemRepresentation]? = self.decode(data: data)
                
                guard let gemRepresentations = possibleGems else {
                    completion(.failure(.badEncode))
                    return
                }
                let gems = gemRepresentations.compactMap { Gem(representation: $0) }
                completion(.success(gems))
                print(gems.count)
            }
        }
    }
    
    func createGem(from gemRepresentation: GemRepresentation, completion: @escaping (Result<Gem, Error>) -> Void) {
        guard let gemData = encode(item: gemRepresentation) else { return }
        var request = gemsURL(with: .post)
        request.httpBody = gemData
        
        perform(request) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                let possibleReturnedGem: ReturnedGem? = self.decode(data: data)
                guard let returnedGem = possibleReturnedGem,
                    let returnedID = returnedGem.gem.first else {
                        completion(.failure(FetchError.badData))
                        return
                }
                var completeGemRepresentation = gemRepresentation
                completeGemRepresentation.id = returnedID
                let gem = Gem(representation: completeGemRepresentation)
                completion(.success(gem))
            }
        }
    }
    
    // MARK: - Users
    
    // Put this in the main coordinator to test the register method
    //        let user = "user123"
    //        let password = "aGoodPassword"
    //        let email = "email@email.com"
    //        NetworkController.shared.register(with: user, password: password, email: email) { result in
    //            switch result {
    //            case .failure(let error): print("\(error)")
    //            case .success(let string): print(string)
    //            }
    //        }
    func register(with username: String, password: String, email: String, completion: @escaping (Result<String, Error>) -> Void) {
        let userToRegister = createUserJSON(username, password, and: email)
        var request = usersURL(with: .post, and: .register)
        request.httpBody = userToRegister
        
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let response = response as? HTTPURLResponse {
                switch response.statusCode {
                case 200...299:
                    print("successfully registered")
                default:
                    print("failed to register")
                }
            }
        }.resume()
        // I suspect we'll need some iteration of the functionality below once the backend starts sending the user id when you register
        
        //        perform(request) { result in
        //            switch result {
        //            case .failure(let error): print(error)
        //            case.success(let data):
        //                let possibleUserRepresentation: UserRepresentation? = self.decode(data: data)
        //                guard var userRepresentation = possibleUserRepresentation else { completion(.failure(FetchError.badData))
        //                    return
        //                }
        //                userRepresentation.password = password
        //                if let user = User(representation: userRepresentation) {
        //                    #warning("Should this be on a background context?")
        //                    do {
        //                        try CoreDataStack.shared.save(context: .context)
        //                        completion(.success(user))
        //                    } catch {
        //                        completion(.failure(NSError()))
        //                    }
        //                }
        //            }
        //        }
    }
    
    func signIn(with username: String, password: String, completion: @escaping (Result<String, Error>) -> Void) {
        let user = createUserJSON(username, password, and: "")
        var request = usersURL(with: .post, and: .login)
        request.httpBody = user
        
        perform(request) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                let returnedUser: ReturnedUser? = self.decode(data: data)
                guard let id = returnedUser?.userID,
                    let email = returnedUser?.email,
                    let token = returnedUser?.token else {
                        completion(.failure(FetchError.badData))
                        return
                }
                User(email: email, id: id, password: password, username: username, token: token, context: .context)
                do {
                    try CoreDataStack.shared.mainContext.save()
                    completion(.success("Yay!"))
                } catch {
                    completion(.failure(FetchError.otherError))
                }
            }
        }
    }
    
    private func createUserJSON(_ username: String, _ password: String, and email: String) -> Data? {
        var json = ""
        if email.isEmpty {
            json = """
            {
            "username": "\(username)",
            "password": "\(password)"
            }
            """
        } else {
            json = """
            {
            "username": "\(username)",
            "password": "\(password)",
            "email": "\(email)"
            }
            """
        }
        
        let jsonData = json.data(using: .utf8)
        guard let unwrapped = jsonData else {
            print("No data!")
            return nil
        }
        return unwrapped
    }
    
    // MARK: - Completed Routes
    
    func markGemCompleted(_ gem: Gem, completedBy: CompletedBy, user: User?, completion: @escaping (Result<String, Error>) -> Void) {
        var request = completedURL(with: .post, and: user)
        let encodedCompletedBy = encode(item: completedBy)
        request.httpBody = encodedCompletedBy
        
        perform(request) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
                return
            case .success(_):
                completion(.success("Completed!"))
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func perform(_ request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) {
        let dataTask = URLSession.shared.dataTask(with: request) { data, response, error in
            
            if let error = error {
                print("NetworkController.fetch Error: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                print("NetworkController.fetch Data is wrong")
                completion(.failure(FetchError.badData))
                return
            }
            //            print(String(data: data, encoding: .utf8))
            completion(.success(data))
        }
        dataTask.resume()
    }
    
    private func decode<T: Codable>(data: Data) -> T? {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let decoded = try jsonDecoder.decode(T.self, from: data)
            return decoded
        } catch {
            print("Error decoding item from data: \(error)")
            return nil
        }
    }
    
    private func encode<T: Codable>(item: T) -> Data? {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
        do{
            let encoded = try jsonEncoder.encode(item)
            return encoded
        } catch {
            print("Error encoding item from data: \(error)")
            return nil
        }
    }
    
    // MARK: - URLs
    
    private func gemsURL(with method: HTTPMethod) -> URLRequest {
        let url = URL(string: baseURL)!
        let endpoint = url.appendingPathComponent("gems")
        var request = URLRequest(url: endpoint)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    
    private func usersURL(with method: HTTPMethod, and userAction: UserAction, for user: User? = nil) -> URLRequest {
        var url = URL(string: baseURL)!
            .appendingPathComponent("users")
            .appendingPathComponent(userAction.rawValue)
        if let user = user {
            url = url.appendingPathComponent("\(user.id)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    
    private func completedURL(with method: HTTPMethod, and user: User?) -> URLRequest {
        var url = URL(string: baseURL)!
            .appendingPathComponent("completed")
        if let user = user {
            url = url.appendingPathComponent("\(user.id)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    
    let thing = """
{
    "message": "Welcome testreg!",
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6InRlc3RyZWciLCJpZCI6NywiaWF0IjoxNTgzODU2MDMzLCJleHAiOjE1ODM5NDI0MzN9.Yhyz9rdFkrWeYW8X-N1l3ZgWEujxRHOS1277_p1iyr4",
    "user_id": 7
    "email" : "email@email.com
}
"""
}