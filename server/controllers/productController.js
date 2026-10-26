
import { v2 as cloudinary } from "cloudinary";
import Product from "../models/Product.js";

// Add Product: /api/product/add
export const addProduct = async (req, res) => {
    try {
        const productData = JSON.parse(req.body.productData);

        const images = req.files || [];

        if (images.length === 0) {
            return res.status(400).json({
                success: false,
                message: "Please upload at least one product image"
            });
        }

        const imagesUrl = await Promise.all(
            images.map(async (item) => {
                const result = await cloudinary.uploader.upload(item.path, {
                    resource_type: "image"
                });
                return result.secure_url;
            })
        );

        await Product.create({
            ...productData,
            image: imagesUrl
        });

        return res.json({
            success: true,
            message: "Product Added"
        });
    } catch (error) {
        console.error("ADD PRODUCT ERROR:", error);
        return res.status(500).json({
            success: false,
            message: error?.message || String(error) || "Product creation failed"
        });
    }
};

// Get Product List
export const productList = async (req, res) => {
    try {
        const products = await Product.find({});
        return res.json({ success: true, products });
    } catch (error) {
        console.error("PRODUCT LIST ERROR:", error);
        return res.status(500).json({
            success: false,
            message: error?.message || String(error)
        });
    }
};

// Get Single Product
export const productById = async (req, res) => {
    try {
        const { id } = req.body;
        const product = await Product.findById(id);
        return res.json({ success: true, product });
    } catch (error) {
        console.error("PRODUCT BY ID ERROR:", error);
        return res.status(500).json({
            success: false,
            message: error?.message || String(error)
        });
    }
};

// Change Product Stock
export const changeStock = async (req, res) => {
    try {
        const { id, inStock } = req.body;
        await Product.findByIdAndUpdate(id, { inStock });
        return res.json({
            success: true,
            message: "Stock Updated"
        });
    } catch (error) {
        console.error("CHANGE STOCK ERROR:", error);
        return res.status(500).json({
            success: false,
            message: error?.message || String(error)
        });
    }
};

