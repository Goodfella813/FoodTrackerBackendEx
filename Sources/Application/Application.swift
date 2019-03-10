import Foundation
import Kitura
import LoggerAPI
import Configuration
import CloudEnvironment
import KituraContracts
import Health
import SwiftKueryORM
import SwiftKueryPostgreSQL
import KituraStencil

public let projectPath = ConfigurationManager.BasePath.project.path
public let health = Health()

extension Meal: Model {
    static var idColumnName = "name"
}

class Persistence {
    static func setUp() {
        let pool = PostgreSQLConnection.createPool(url: URL(string: "postgres://vbminjqb:o5PezjtMjtfS9SQ9ntMSTWrbjLRn7Qq-@isilo.db.elephantsql.com:5432/vbminjqb")!, poolOptions: ConnectionPoolOptions(initialCapacity: 1, maxCapacity: 3, timeout: 10000))
        Database.default = Database(pool)
    }
    
}

public class App {
    let router = Router()
    let cloudEnv = CloudEnv()
    //    added
    private var fileManager = FileManager.default
    private var rootPath = StaticFileServer().absoluteRootPath
    
    public init() throws {
        // Run the metrics initializer
        initializeMetrics(router: router)
    }

    func postInit() throws {
        // Endpoints
        initializeHealthRoutes(app: self)
        
        //        added
        router.post("/meals", handler: storeHandler)
        router.get("/meals", handler: loadHandler)
        
        router.get("/images", middleware: StaticFileServer())
        
        router.add(templateEngine: StencilTemplateEngine())
        
        router.get("/foodtracker") { request, response, next in
            Meal.findAll { (result: [Meal]?, error: RequestError?) in
                guard let meals = result else {
                    return
                }
                var allMeals: [String: [[String: Any]]] = ["meals" : []]
                for meal in meals {
                    allMeals["meals"]?.append(["name": meal.name, "rating": meal.rating])
                }
                do {
                    try response.render("Example.stencil", context: allMeals)
                } catch let error {
                    response.send(json: ["Error": error.localizedDescription])
                }
                next()
            }
        }
        router.post("/foodtracker", middleware: BodyParser())
        router.post("/foodtracker") { request, response, next in
            try response.redirect("/foodtracker")
            guard let parsedBody = request.body else {
                next()
                return
            }
            let parts = parsedBody.asMultiPart
            guard let name = parts?[0].body.asText,
                let stringRating = parts?[1].body.asText,
                let rating = Int(stringRating),
                case .raw(let photo)? = parts?[2].body,
                parts?[2].type == "image/jpeg",
                let newMeal = Meal(name: name, photo: photo, rating: rating)
            else {
                next()
                return
            }
            let path = "\(self.rootPath)/\(newMeal.name).jpg"
            self.fileManager.createFile(atPath: path, contents: newMeal.photo)
            newMeal.save { (meal: Meal?, error: RequestError?) in
                next()
            }
        }
        
        router.get("/summary", handler: summaryHandler)
        router.delete("/meal", handler: deleteHandler)
        
        Persistence.setUp()
        do {
            try Meal.createTableSync()
        } catch let error {
            print(error)
        }
    }

    public func run() throws {
        try postInit()
        Kitura.addHTTPServer(onPort: cloudEnv.port, with: router)
        Kitura.run()
    }
    
    func storeHandler(meal: Meal, completion: @escaping (Meal?, RequestError?) -> Void) {
        let path = "\(self.rootPath)/\(meal.name).jpg"
        fileManager.createFile(atPath: path, contents: meal.photo)
        meal.save(completion)
    }
    
    func loadHandler(completion: @escaping ([Meal]?, RequestError?) -> Void) {
        Meal.findAll(completion)
    }
    
    func summaryHandler(completion: @escaping (Summary?, RequestError?) -> Void) {
        Meal.findAll { meals, error in
            guard let meals = meals else {
                completion(nil, .internalServerError)
                return
            }
            completion(Summary(meals), nil)
        }
    }
    
    func deleteHandler(id: String, completion: @escaping (RequestError?) -> Void) {
        Meal.delete(id: id, completion)
    }
}
